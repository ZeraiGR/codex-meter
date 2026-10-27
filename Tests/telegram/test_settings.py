import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'integrations/telegram'))
import bot
import control


class FakeTelegram:
    updates = []
    calls = []
    def __init__(self, token, directory):self.token=token
    def call(self, method, **payload):
        self.calls.append((self.token, method, payload))
        if method == 'getMe':return {'username': 'synthetic_bot'}
        if method == 'getWebhookInfo':return {'url': ''}
        if method == 'getUpdates':return self.updates
        return True


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'telegram';self.agents=Path(self.temp.name)/'agents'
        self.loaded=False
        def launch(*args):
            if args[0]=='print':return 0 if self.loaded else 1
            self.loaded=args[0]=='bootstrap'
            return 0
        self.controller=control.Controller(self.root,self.agents,FakeTelegram,launch)
        FakeTelegram.updates=[];FakeTelegram.calls=[]
        self.options=dict(meter=sys.executable,codex=sys.executable,workspace=self.temp.name,
                          permissions=control.DEFAULT_PERMISSIONS.copy())
    def call(self, action, **kwargs):return self.controller.dispatch(dict(self.options,action=action,**kwargs))
    def pair(self, owner=123, token='synthetic-token'):
        self.call('begin',token=token)
        pending=self.controller.read('pairing.json')
        FakeTelegram.updates=[dict(update_id=2,message=dict(text='/start '+pending['nonce'],chat=dict(type='private',id=owner),**{'from':dict(id=owner)}))]
        return self.call('pair')
    def test_clean_install_has_no_identity_or_enabled_service(self):
        status=self.call('status')
        self.assertFalse(status['connected']);self.assertFalse(status['running'])
        self.assertFalse(status['permissions']['codex'])
        self.assertFalse((self.root/'token').exists())
        self.assertFalse(self.agents.exists())
    def test_pairing_is_explicit_private_and_new_owner_never_gets_old_queue(self):
        result=self.pair()
        self.assertTrue(result['connected']);self.assertTrue(result['running'])
        self.assertEqual(result['owner_id'],123)
        self.assertNotIn('synthetic-token',json.dumps(result))
        self.assertEqual((self.root/'token').stat().st_mode & 0o777,0o600)
        self.assertEqual(self.root.stat().st_mode & 0o777,0o700)
        bot.save(self.root/'state.json',dict(outbox=['old reply'],sessions={'1':{'thread':'private-thread'}}))
        result=self.pair(456,'another-token')
        self.assertEqual(result['owner_id'],456)
        self.assertNotIn('private-thread',(self.root/'state.json').read_text())
        self.assertEqual(self.controller.read('state.json')['outbox'],[])
    def test_standard_pairing_never_inherits_advanced_codex_access(self):
        self.options['permissions']['codex']=True
        result=self.pair()
        self.assertFalse(result['permissions']['codex'])
    def test_pairing_rejects_foreign_group_and_wrong_nonce(self):
        self.call('begin',token='synthetic-token')
        nonce=self.controller.read('pairing.json')['nonce']
        FakeTelegram.updates=[dict(update_id=1,message=dict(text='/start '+nonce,chat=dict(type='group',id=123),**{'from':dict(id=123)})),
                              dict(update_id=2,message=dict(text='/start wrong',chat=dict(type='private',id=123),**{'from':dict(id=123)}))]
        result=self.call('pair');self.assertFalse(result['connected'])
        self.assertFalse((self.root/'token').exists())
    def test_cancel_and_expiry_preserve_existing_connection(self):
        self.pair();old=(self.root/'token').read_text()
        self.call('begin',token='replacement');self.call('cancel')
        self.assertEqual((self.root/'token').read_text(),old);self.assertTrue(self.loaded)
        self.call('begin',token='replacement')
        pending=self.controller.read('pairing.json');pending['expires']=0;bot.save(self.root/'pairing.json',pending)
        with self.assertRaises(RuntimeError):self.call('pair')
        self.assertEqual((self.root/'token').read_text(),old)
    def test_settings_preserve_sessions_and_reject_running_requests(self):
        self.pair();state=dict(sessions={'1':dict(thread='kept',running=True)},outbox=[])
        bot.save(self.root/'state.json',state)
        with self.assertRaises(RuntimeError):self.call('save')
        self.assertTrue(self.loaded)
        state['sessions']['1']['running']=False;bot.save(self.root/'state.json',state)
        self.options['permissions']['limits']=False
        result=self.call('save')
        self.assertFalse(result['permissions']['limits']);self.assertTrue(result['running'])
        self.assertEqual(self.controller.read('state.json')['sessions'],state['sessions'])
        self.call('stop');self.assertFalse(self.loaded)
        self.assertTrue((self.root/'token').exists())
        self.call('start');self.assertTrue(self.loaded)
        self.call('disconnect');self.assertFalse((self.root/'token').exists())
        self.assertFalse(self.loaded)
    def test_failed_pairing_write_restores_old_identity_and_state(self):
        self.pair();bot.save(self.root/'state.json',{'outbox':['kept']})
        before={name:(self.root/name).read_bytes() for name in ('config.json','token','state.json','network.json')}
        self.call('begin',token='replacement')
        pending=self.controller.read('pairing.json')
        FakeTelegram.updates=[dict(update_id=3,message=dict(text='/start '+pending['nonce'],chat=dict(type='private',id=456),**{'from':dict(id=456)}))]
        with patch.object(self.controller,'network',side_effect=OSError('disk full')):
            with self.assertRaises(RuntimeError):self.call('pair')
        for name,data in before.items():self.assertEqual((self.root/name).read_bytes(),data)
        self.assertFalse(self.loaded)
        self.call('start');self.assertTrue(self.loaded)
    def test_failed_settings_write_restores_values_and_keeps_token(self):
        self.pair();before=(self.root/'config.json').read_bytes()
        self.options['permissions']['limits']=False
        with patch.object(self.controller,'network',side_effect=OSError('disk full')):
            with self.assertRaises(RuntimeError):self.call('save')
        self.assertEqual((self.root/'config.json').read_bytes(),before)
        self.assertEqual((self.root/'token').read_text(),'synthetic-token')
    def test_disconnect_does_not_archive_bot_credentials(self):
        self.pair();self.call('disconnect')
        self.assertFalse((self.root/'token').exists())
        self.assertFalse((self.root/'previous/token').exists())
    def test_start_failure_keeps_pairing_for_explicit_retry(self):
        self.controller.launch=lambda *args:1
        with self.assertRaises(RuntimeError):self.pair()
        self.assertTrue(self.call('status')['connected'])
        self.assertEqual((self.root/'token').read_text(),'synthetic-token')

    def test_legacy_permissions_remain_enabled_until_explicit_save(self):
        self.root.mkdir();(self.root/'token').write_text('legacy')
        bot.save(self.root/'config.json',dict(owner_id=123))
        self.assertTrue(all(self.call('status')['permissions'].values()))
    def test_invalid_options_do_not_mutate_connection(self):
        self.pair();before=(self.root/'config.json').read_bytes()
        for bad in [dict(tunnel_port=-1),dict(max_parallel=9),dict(reminder_hours=[0]),dict(sandbox='danger-full-access')]:
            with self.assertRaises(RuntimeError):self.call('save',**bad)
            self.assertEqual((self.root/'config.json').read_bytes(),before)


class PermissionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.permissions=dict.fromkeys(control.DEFAULT_PERMISSIONS,False)
        self.api=FakeTelegram('test',Path(self.temp.name));FakeTelegram.calls=[]
        self.bridge=bot.Bot(dict(owner_id=123,workspace=self.temp.name,permissions=self.permissions),Path(self.temp.name),self.api)
        self.bridge.next_refresh=time.time()+3600;self.addCleanup(self.bridge.close)
    def send(self,text):
        self.bridge.handle(dict(message=dict(chat=dict(type='private',id=123),**{'from':dict(id=123)},text=text,date=time.time())))
    def test_disabled_commands_cannot_run_codex_or_read_quota(self):
        with patch.object(self.bridge.pool,'submit') as submit:
            for text in ['/limits','/new Secret','/sessions','/use 1','execute something','/status','/help']:self.send(text)
            self.bridge.tick();submit.assert_not_called()
        text=json.dumps(self.bridge.state['outbox'],ensure_ascii=False)
        self.assertNotIn(self.temp.name,text)
        self.assertFalse(self.bridge.want_limits);self.assertEqual(len(self.bridge.sessions),1)
    def test_revoked_categories_and_legacy_queue_are_not_delivered(self):
        for entry in [dict(text='private answer',category='codex'),dict(text='quota',category='limits'),
                      dict(text='reminder',category='reminders'),dict(text='changed',category='window_changes'),'legacy reply']:
            self.bridge.state['outbox']=[entry];self.bridge.tick()
        self.assertFalse(any(method=='sendMessage' for _,method,_ in FakeTelegram.calls))
    def test_allowed_quota_is_independent_of_codex(self):
        self.permissions['limits']=True
        future=concurrent.futures.Future()
        with patch.object(self.bridge.pool,'submit',return_value=future) as submit:
            self.send('/limits');self.bridge.tick();submit.assert_called_once()
            future.set_result({});self.bridge.tick()
        self.assertTrue(any(method=='sendMessage' for _,method,_ in FakeTelegram.calls))
        self.assertEqual(self.bridge.jobs,{})
    def test_session_list_and_help_are_classified_for_permission_changes(self):
        self.permissions['codex']=True
        self.send('/sessions');self.send('/help')
        self.assertTrue(all(entry['category']=='codex' for entry in self.bridge.state['outbox']))
        self.permissions['codex']=False
        while self.bridge.state['outbox']:self.bridge.tick()
        self.assertFalse(any(method=='sendMessage' for _,method,_ in FakeTelegram.calls))


if __name__=='__main__':unittest.main()
