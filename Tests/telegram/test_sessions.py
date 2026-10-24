import concurrent.futures
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from test_bot import bot


class Telegram:
    def __init__(self):
        self.calls = []

    def call(self, method, **kwargs):
        self.calls.append((method, kwargs))
        return {}


class SessionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.telegram = Telegram()
        self.config = dict(owner_id=123, workspace=self.temp.name, max_parallel=2)
        self.bridge = self.make_bridge()

    def make_bridge(self):
        bridge = bot.Bot(self.config, self.directory, self.telegram)
        bridge.next_refresh = time.time() + 3600
        self.addCleanup(bridge.close)
        return bridge

    def send(self, text, owner=123, date=None):
        self.bridge.handle(dict(message=dict(chat=dict(type='private', id=owner),
            **{'from': dict(id=owner)}, text=text, date=date or time.time())))

    def test_legacy_migration_preserves_thread_queue_offset_quota(self):
        old = dict(thread='legacy-thread', running=True, offset=42, outbox=['pending'],
                   snapshot={'fetchedAt': 7}, window={'sent': [48]})
        bot.save(self.directory / 'state.json', old)
        bridge = self.make_bridge()
        self.assertEqual(bridge.sessions['1']['thread'], 'legacy-thread')
        self.assertEqual(bridge.state['offset'], 42)
        self.assertEqual(bridge.state['snapshot'], old['snapshot'])
        self.assertEqual(bridge.state['window'], old['window'])
        self.assertEqual(bridge.state['outbox'][0], 'pending')
        self.assertIn('[1: Основной]', bridge.state['outbox'][1])
        self.assertFalse(bridge.sessions['1'].get('running'))
        self.assertEqual(bridge.jobs, {})
        restarted = self.make_bridge()
        self.assertEqual(restarted.state, bridge.state)

    def test_parallel_completion_routes_to_origin_and_resumes_correct_thread(self):
        futures = [concurrent.futures.Future() for _ in range(3)]
        with patch.object(self.bridge.pool, 'submit', side_effect=futures) as submit:
            self.send('first')
            self.send('/new Второй')
            self.send('second')
            self.send('duplicate')
            self.assertEqual(submit.call_count, 2)
            futures[1].set_result(('thread-two', 'answer two'))
            self.bridge.tick()
            futures[0].set_result(('thread-one', 'answer one'))
            self.bridge.tick()
            self.assertEqual(self.bridge.sessions['1']['thread'], 'thread-one')
            self.assertEqual(self.bridge.sessions['2']['thread'], 'thread-two')
            self.assertIn('[1: Основной]\nanswer one', self.bridge.state['outbox'])
            self.assertIn('[2: Второй]\nanswer two', self.bridge.state['outbox'])
            self.send('/use 1')
            self.send('continue')
            self.assertEqual(submit.call_args.args[1:], ('continue', 'thread-one'))
            futures[2].set_result(('thread-one', 'done'))
            self.bridge.tick()
        restarted = self.make_bridge()
        self.assertEqual(restarted.state['active_session'], '1')
        self.assertEqual(restarted.sessions['2']['thread'], 'thread-two')

    def test_limit_cancel_and_quota_are_independent(self):
        futures = [concurrent.futures.Future() for _ in range(3)]
        with patch.object(self.bridge.pool, 'submit', side_effect=futures) as submit:
            self.send('one')
            self.send('/new Two')
            self.send('two')
            self.send('/new Three')
            self.send('three')
            self.assertEqual(submit.call_count, 2)
            self.send('/use 1')
            self.send('/cancel')
            self.assertTrue(self.bridge.jobs['1'][0].cancelled.is_set())
            self.assertFalse(self.bridge.jobs['2'][0].cancelled.is_set())
            self.send('/limits')
            self.bridge.tick()
            self.assertEqual(submit.call_count, 3)
            self.assertEqual(submit.call_args.args, (self.bridge.refresh,))
            futures[0].set_exception(RuntimeError('failure'))
            futures[1].set_result(('two', 'ok'))
            futures[2].set_result({})
            self.bridge.tick()
            self.assertEqual(self.bridge.jobs, {})
            self.assertFalse(self.bridge.sessions['1']['running'])

    def test_buttons_pagination_authorization_and_unknown_session(self):
        for i in range(10):
            self.send('/new Session ' + str(i))
        self.send('/sessions')
        entry = self.bridge.state['outbox'][-1]
        self.assertEqual(len(entry['reply_markup']['inline_keyboard']), 9)
        def click(data, owner=123, chat_type='private'):
            self.bridge.handle(dict(callback_query=dict(id='callback', data=data,
                **{'from': dict(id=owner)}, message=dict(chat=dict(id=123, type=chat_type)))))
        click('use:1', 999)
        click('use:1', chat_type='group')
        self.assertEqual(self.bridge.state['active_session'], '11')
        click('use:1')
        self.assertEqual(self.bridge.state['active_session'], '1')
        click('use:missing')
        self.assertEqual(self.bridge.state['active_session'], '1')
        click('sessions:1')
        self.assertIn('[1: Основной]', self.bridge.state['outbox'][-1]['text'])
        self.assertEqual(self.telegram.calls[-1][0], 'answerCallbackQuery')
        self.bridge.state['outbox'] = [entry]
        self.bridge.tick()
        self.assertEqual(self.telegram.calls[-1][1]['reply_markup'], entry['reply_markup'])

    def test_reject_stale_foreign_messages_and_preserve_running_on_restart(self):
        with patch.object(self.bridge.pool, 'submit') as submit:
            self.send('foreign', owner=999)
            self.send('stale', date=time.time()-601)
            submit.assert_not_called()
        self.bridge.sessions['1']['running'] = True
        self.bridge.persist()
        restarted = self.make_bridge()
        self.assertEqual(restarted.jobs, {})
        self.assertIn('автоматически не повторён', restarted.state['outbox'][-1])

    def test_chunks_keep_labels_and_survive_send_failure(self):
        self.bridge.enqueue('😀' * 4500, sid='1')
        chunks = list(self.bridge.state['outbox'])
        for chunk in chunks:
            self.assertTrue(chunk.startswith('[1: Основной]\n'))
            self.assertLessEqual(len(chunk.encode('utf-16-le'))//2, 4096)
        with patch.object(self.telegram, 'call', side_effect=RuntimeError('offline')):
            with self.assertRaises(RuntimeError):
                self.bridge.tick()
        self.assertEqual(json.loads(self.bridge.state_path.read_text())['outbox'], chunks)

    def test_real_processes_run_concurrently_and_cancel_only_selected(self):
        executable = self.directory / 'fake-codex'
        executable.write_text('''#!/usr/bin/env python3
import json, pathlib, sys, time
prompt = sys.stdin.read()
pathlib.Path(prompt + '.started').touch()
print(json.dumps({'type': 'thread.started', 'thread_id': prompt}), flush=True)
while not pathlib.Path(prompt + '.release').exists():
    time.sleep(.01)
print(json.dumps({'type': 'item.completed', 'item': {'type': 'agent_message', 'text': prompt}}))
print(json.dumps({'type': 'turn.completed'}))
''')
        executable.chmod(0o700)
        self.bridge.config['codex'] = str(executable)
        self.send('one')
        self.send('/new Two')
        self.send('two')
        deadline = time.time()+5
        while not all((self.directory / (name+'.started')).exists() for name in ('one', 'two')):
            self.assertLess(time.time(), deadline)
            time.sleep(.01)
        self.send('/use 1')
        self.send('/cancel')
        self.assertIn('остановлен', self.bridge.jobs['1'][1].result(timeout=5)[1])
        self.assertFalse(self.bridge.jobs['2'][1].done())
        (self.directory / 'two.release').touch()
        self.assertEqual(self.bridge.jobs['2'][1].result(timeout=5), ('two', 'two'))
        self.bridge.tick()
        self.assertEqual(self.bridge.jobs, {})


if __name__ == '__main__':
    unittest.main()
