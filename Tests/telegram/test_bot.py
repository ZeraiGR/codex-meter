import importlib.util
import io
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('meter_bot', Path(__file__).resolve().parents[2] / 'integrations/telegram/bot.py')
bot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bot)


class BridgeTests(unittest.TestCase):
    def snapshot(self, now, hours=12, used=20):
        return dict(accountKey='test', fetchedAt=now-bot.APPLE_EPOCH,
                    buckets=[dict(limitId='codex', primary=dict(windowDurationMins=10080, usedPercent=used, resetsAt=now+hours*3600))])

    def test_reminder_urgent_only_jitter_restart_and_new_window(self):
        now = time.time()
        state = {}
        snapshot = self.snapshot(now)
        self.assertEqual(len(bot.reminders(snapshot, state, now)), 1)
        self.assertEqual(state['window']['sent'], [24, 48])
        state = json.loads(json.dumps(state))
        snapshot['buckets'][0]['primary']['resetsAt'] += 1
        self.assertEqual(bot.reminders(snapshot, state, now), [])
        later = now+7*3600
        snapshot['fetchedAt'] = later-bot.APPLE_EPOCH
        self.assertEqual(len(bot.reminders(snapshot, state, later)), 1)
        self.assertEqual(bot.reminders(snapshot, state, later), [])
        snapshot = self.snapshot(later, hours=168, used=0)
        self.assertEqual(len(bot.reminders(snapshot, state, later)), 1)
        snapshot['buckets'][0]['primary']['resetsAt'] += 200
        snapshot['fetchedAt'] += 200
        self.assertEqual(bot.reminders(snapshot, state, later+200), [])

    def test_stale_expired_zero_remaining_and_provisional_do_not_remind(self):
        now = time.time()
        for snapshot in [self.snapshot(now-500), self.snapshot(now, hours=-1),
                         self.snapshot(now, used=100), self.snapshot(now, hours=168, used=0)]:
            self.assertEqual(bot.reminders(snapshot, {}, now), [])
        self.assertIn('УСТАРЕВШИЕ', bot.quota_text(self.snapshot(now-500), now))
        self.assertIn('предварительный', bot.quota_text(self.snapshot(now, hours=168, used=0), now))
        self.assertIn('не подтверждён', bot.quota_text(self.snapshot(now, hours=-1), now))

    def test_authorization_rejects_groups_other_users_and_spoofs(self):
        allowed = dict(chat=dict(type='private', id=123), **{'from': dict(id=123)})
        self.assertTrue(bot.authorized(allowed, 123))
        for msg in [dict(chat=dict(type='group', id=123), **{'from': dict(id=123)}),
                    dict(chat=dict(type='private', id=123), **{'from': dict(id=456)}), {},
                    dict(chat=dict(type='private', id=456), **{'from': dict(id=123)})]:
            self.assertFalse(bot.authorized(msg, 123))

    def test_secret_redaction(self):
        with tempfile.TemporaryDirectory() as temp, \
                patch.object(bot.urllib.request, 'urlopen', side_effect=RuntimeError('secret-token')):
            with self.assertRaises(RuntimeError) as error:
                bot.Telegram('secret-token', Path(temp)).call('getMe')
            self.assertNotIn('secret-token', str(error.exception))

    def test_tunnel_preserves_telegram_tls_and_closes_connection(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            bot.save(directory / 'network.json', {'tunnel_port': 18443})
            with patch.object(bot.socket, 'create_connection') as connect, \
                    patch.object(bot.ssl, 'create_default_context') as context, \
                    patch.object(bot.http.client, 'HTTPSConnection') as https, \
                    patch.object(bot.urllib.request, 'urlopen') as direct:
                https.return_value.getresponse.return_value = io.BytesIO(b'{"ok":true,"result":{"id":123}}')
                self.assertEqual(bot.Telegram('test-token', directory).call('getMe'), {'id': 123})
                connect.assert_called_once_with(('127.0.0.1', 18443), timeout=35)
                self.assertEqual(context.return_value.wrap_socket.call_args.kwargs['server_hostname'], 'api.telegram.org')
                direct.assert_not_called()
                https.return_value.close.assert_called_once()

    def test_tunnel_failure_does_not_fall_back_or_leak_token(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            bot.save(directory / 'network.json', {'tunnel_port': 18443})
            with patch.object(bot.socket, 'create_connection', side_effect=OSError('secret-token')), \
                    patch.object(bot.urllib.request, 'urlopen') as direct:
                with self.assertRaises(RuntimeError) as error:
                    bot.Telegram('secret-token', directory).call('getMe')
                self.assertNotIn('secret-token', str(error.exception))
                direct.assert_not_called()

    def test_invalid_tunnel_port(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for port in [True, '18443', 0, 65536]:
                bot.save(directory / 'network.json', {'tunnel_port': port})
                with self.assertRaises(RuntimeError):
                    bot.Telegram('test-token', directory)

    def test_queue_survives_failed_send_and_commands_do_not_run_models(self):
        class Telegram:
            def call(self, *args, **kwargs):
                raise RuntimeError('offline')
        with tempfile.TemporaryDirectory() as temp:
            bridge = bot.Bot(dict(owner_id=123, workspace=temp), Path(temp), Telegram())
            bridge.next_refresh = time.time()+60
            bridge.enqueue('test')
            with self.assertRaises(RuntimeError):
                bridge.tick()
            self.assertEqual(json.loads(bridge.state_path.read_text())['outbox'], ['test'])
            bridge.handle(dict(message=dict(chat=dict(type='private', id=999), **{'from': dict(id=999)}, text='execute')))
            self.assertEqual(bridge.jobs, {})
            bridge.handle(dict(message=dict(chat=dict(type='private', id=123), **{'from': dict(id=123)}, text='/limits')))
            self.assertTrue(bridge.want_limits)
            self.assertEqual(bridge.jobs, {})
            bridge.pool.shutdown()

    def test_codex_new_resume_failure_and_cancel(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / 'codex'
            executable.write_text('#!/usr/bin/env python3\nimport json,sys\n'
                                  'prompt=sys.stdin.read()\n'
                                  'print(json.dumps({"type":"thread.started","thread_id":"test-thread"}))\n'
                                  'print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":prompt}}))\n'
                                  'print(json.dumps({"type":"turn.completed"}))\n')
            executable.chmod(0o700)
            job = bot.CodexJob(dict(codex=str(executable), workspace=temp, sandbox='workspace-write'))
            self.assertEqual(job.run('hello `$(safe)`', None), ('test-thread', 'hello `$(safe)`'))
            self.assertEqual(job.run('next', 'test-thread'), ('test-thread', 'next'))
            executable.write_text('#!/bin/sh\nexit 1\n')
            self.assertIn('не завершил', job.run('hello', None)[1])
            executable.write_text('#!/bin/sh\nsleep 60\n')
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as pool:
                future = pool.submit(job.run, 'hello', None)
                for _ in range(100):
                    if job.process and job.process.poll() is None:
                        break
                    time.sleep(.01)
                job.cancel()
                self.assertIn('остановлен', future.result(timeout=3)[1])


if __name__ == '__main__':
    unittest.main()
