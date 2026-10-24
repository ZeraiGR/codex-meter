#!/usr/bin/env python3
"""Private Telegram bridge. Standard library only; secrets stay outside the repo."""
import argparse
import concurrent.futures
import datetime as dt
import fcntl
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.request

ROOT = Path.home() / 'Library/Application Support/CodexMeter/telegram'
APPLE_EPOCH = 978307200


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def stamp(value):
    return dt.datetime.fromtimestamp(value).astimezone().strftime('%d.%m.%Y %H:%M %Z')


def windows(snapshot):
    for bucket in snapshot.get('buckets', []):
        if bucket.get('limitId', 'codex') == 'codex':
            return [bucket[k] for k in ('primary', 'secondary') if bucket.get(k)]
    return []


def provisional(window, snapshot):
    reset = window.get('resetsAt')
    duration = (window.get('windowDurationMins') or 0) * 60
    return bool(window.get('resetIsProvisional') or (
        reset and duration > 0 and window.get('usedPercent') == 0
        and reset - (snapshot.get('fetchedAt', 0) + APPLE_EPOCH) >= duration - 120))


def fresh(snapshot, now):
    age = now - (snapshot.get('fetchedAt', 0) + APPLE_EPOCH)
    return bool(snapshot.get('buckets')) and -60 <= age < 180


def quota_text(snapshot, now):
    if not snapshot or not snapshot.get('buckets'):
        return 'Лимиты пока недоступны. Нужен успешный запрос к Codex.'
    lines = ['Лимиты Codex' if fresh(snapshot, now) else 'УСТАРЕВШИЕ данные: текущий остаток неизвестен.']
    lines.append('Измерение: ' + stamp(snapshot['fetchedAt'] + APPLE_EPOCH))
    for w in windows(snapshot):
        mins = w.get('windowDurationMins')
        label = 'Неделя' if mins == 10080 else f'{mins or "?"} мин'
        remaining = max(0, min(100, 100 - w['usedPercent']))
        lines.append(f'{label}: осталось {remaining:g}% квоты.')
        reset = w.get('resetsAt')
        if reset is None:
            lines.append('Дата сброса неизвестна.')
        elif provisional(w, snapshot):
            lines.append('Срок предварительный, сервер может сдвигать его при нулевом расходе: ' + stamp(reset))
        elif reset <= now:
            lines.append('Прежний срок истёк; факт восстановления ещё не подтверждён.')
        else:
            lines.append('Сброс по последнему ответу сервера: ' + stamp(reset))
    lines.append('Проценты квоты не равны фиксированному числу токенов.')
    return '\n'.join(lines)


def reminders(snapshot, state, now, hours=(48, 24, 6)):
    """Return messages and updated dedupe state; caller persists messages atomically."""
    result = []
    if not fresh(snapshot, now):
        return result
    weekly = next((w for w in windows(snapshot) if w.get('windowDurationMins') == 10080), None)
    if not weekly or not weekly.get('resetsAt'):
        return result
    reset = weekly['resetsAt']
    account = snapshot['accountKey']
    old = state.get('window')
    moving = provisional(weekly, snapshot)
    if old and old['account'] == account and abs(old['reset'] - reset) > 90:
        if not old.get('provisional'):
            result.append('Сервер изменил недельное окно. Прежний срок: ' + stamp(old['reset'])
                          + '. Точное время изменения между опросами неизвестно.\n' + quota_text(snapshot, now))
    same = old and old['account'] == account and abs(old['reset'] - reset) <= 90
    sent = old.get('sent', []) if same else []
    anchor = old['reset'] if same else reset
    remaining = max(0, 100 - weekly['usedPercent'])
    eligible = [h for h in hours if h not in sent and 0 < reset-now <= h*3600]
    if not moving and remaining > 0 and eligible:
        stage = min(eligible)
        result.append(f'До недельного сброса по данным сервера меньше {stage} ч. '
                      f'Осталось {remaining:g}% квоты. Срок: {stamp(reset)}. Можно запланировать задачи.')
        sent = sorted(set(sent) | {h for h in hours if h >= stage})
    state['window'] = dict(account=account, reset=anchor, provisional=moving, sent=sent)
    return result


class Telegram:
    def __init__(self, token, directory=ROOT):
        self.token = token
        network = directory / 'network.json'
        settings = json.loads(network.read_text()) if network.exists() else {}
        self.tunnel_port = settings.get('tunnel_port')
        if self.tunnel_port is not None and (type(self.tunnel_port) is not int
                                             or not 1 <= self.tunnel_port <= 65535):
            raise RuntimeError('В network.json нужен tunnel_port от 1 до 65535.')

    def call(self, method, **payload):
        request = urllib.request.Request('https://api.telegram.org/bot' + self.token + '/' + method,
                                         data=json.dumps(payload).encode(),
                                         headers={'Content-Type': 'application/json'})
        # Never propagate URL-bearing exceptions: the URL contains the bot token.
        try:
            if self.tunnel_port is None:
                with urllib.request.urlopen(request, timeout=35) as response:
                    data = json.load(response)
            else:
                # SSH forwards raw TCP; TLS still authenticates Telegram end to end.
                connection = http.client.HTTPSConnection('api.telegram.org', timeout=35)
                try:
                    with socket.create_connection(('127.0.0.1', self.tunnel_port), timeout=35) as raw:
                        connection.sock = ssl.create_default_context().wrap_socket(
                            raw, server_hostname='api.telegram.org')
                        connection.request('POST', request.selector, body=request.data,
                                           headers={'Content-Type': 'application/json'})
                        data = json.load(connection.getresponse())
                finally:
                    connection.close()
            if not data.get('ok'):
                raise RuntimeError('Telegram отклонил запрос')
            return data['result']
        except Exception:
            raise RuntimeError('Telegram недоступен или отклонил запрос') from None


def authorized(message, owner):
    return (message.get('chat', {}).get('type') == 'private'
            and message.get('chat', {}).get('id') == owner
            and message.get('from', {}).get('id') == owner
            and not message.get('from', {}).get('is_bot', False))


class CodexJob:
    def __init__(self, config):
        self.config = config
        self.process = None
        self.lock = threading.Lock()
        self.cancelled = threading.Event()

    def cancel(self):
        self.cancelled.set()
        with self.lock:
            process = self.process
            if process and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    return
                def force_stop():
                    if process.poll() is None:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                timer = threading.Timer(5, force_stop)
                timer.daemon = True
                timer.start()

    def run(self, prompt, thread):
        # No shell interpolation, no Telegram credentials in child environment.
        args = [self.config['codex'], 'exec', '-c', 'approval_policy="never"',
                '-c', 'sandbox_mode=' + json.dumps(self.config.get('sandbox', 'read-only')),
                '--json', '--skip-git-repo-check']
        if thread:
            args += ['resume', thread, '-']
        else:
            args += ['-']
        with tempfile.TemporaryFile(mode='w+b') as output:
            with self.lock:
                if self.cancelled.is_set():
                    return thread, 'Запрос остановлен.'
                self.process = subprocess.Popen(args, cwd=self.config['workspace'], stdin=subprocess.PIPE,
                    stdout=output, stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                self.process.communicate(prompt.encode(), timeout=1800)
            except subprocess.TimeoutExpired:
                self.cancel()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
                return thread, 'Запрос остановлен по таймауту (30 минут).'
            output.seek(0)
            answer = []
            completed = False
            for raw in output:
                try:
                    event = json.loads(raw)
                except (ValueError, UnicodeError):
                    continue
                if event.get('type') == 'thread.started':
                    thread = event.get('thread_id', thread)
                if event.get('type') == 'turn.completed':
                    completed = True
                item = event.get('item', {})
                if event.get('type') == 'item.completed' and item.get('type') == 'agent_message':
                    answer.append(item.get('text', ''))
            if self.cancelled.is_set():
                return thread, 'Запрос остановлен.'
            if self.process.returncode or not completed:
                return thread, 'Codex не завершил запрос. Проверь вход и сетевой launcher на Mac; /new начинает новый диалог.'
            return thread, '\n\n'.join(answer) or 'Codex завершил запрос без текстового ответа.'


class Bot:
    def __init__(self, config, directory=ROOT, telegram=None):
        self.config = config
        self.directory = directory
        self.state_path = directory / 'state.json'
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        self.telegram = telegram or Telegram((directory / 'token').read_text().strip(), directory)
        self.owner = config['owner_id']
        self.max_parallel = config.get('max_parallel', 3)
        if type(self.max_parallel) is not int or not 1 <= self.max_parallel <= 8:
            raise ValueError('max_parallel должен быть целым числом от 1 до 8.')
        # Reserve a worker for quota even when every Codex slot is occupied.
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=self.max_parallel + 1)
        self.jobs = {}
        if 'sessions' not in self.state:
            self.state['sessions'] = {'1': dict(title='Основной',
                thread=self.state.pop('thread', None), running=self.state.pop('running', False))}
            self.state['active_session'] = '1'
        self.sessions = self.state['sessions']
        if self.state.get('active_session') not in self.sessions:
            self.state['active_session'] = next(iter(self.sessions), None)
        if not self.sessions:
            self.create_session('Основной')
        self.quota_future = None
        self.next_refresh = 0
        self.snapshot = self.state.get('snapshot', {})
        self.want_limits = False
        for sid, session in self.sessions.items():
            if session.pop('running', False):
                self.enqueue('Бот перезапущен во время запроса. Запрос автоматически не повторён; отправь его заново.', sid=sid)
        self.persist()

    def create_session(self, title):
        sid = str(max((int(key) for key in self.sessions), default=0) + 1)
        self.sessions[sid] = dict(title=' '.join(title.split())[:80] or 'Диалог ' + sid,
                                  thread=None, running=False)
        self.state['active_session'] = sid
        self.persist()
        return sid

    def label(self, sid):
        return '[' + sid + ': ' + self.sessions[sid]['title'] + ']'

    def select_session(self, sid):
        if sid not in self.sessions:
            self.enqueue('Сессия не найдена. /sessions')
            return
        self.state['active_session'] = sid
        self.enqueue('Сессия выбрана. Следующее сообщение отправится сюда.', sid=sid)

    def list_sessions(self, page=0):
        keys = list(reversed(self.sessions))
        page = max(0, min(page, (len(keys) - 1) // 8))
        lines, buttons = [], []
        for sid in keys[page*8:(page+1)*8]:
            marker = '→ ' if sid == self.state['active_session'] else ''
            status = 'работает' if sid in self.jobs else 'готова'
            lines.append(marker + self.label(sid) + ' — ' + status)
            buttons.append([dict(text=marker + sid + ': ' + self.sessions[sid]['title'][:40],
                                 callback_data='use:' + sid)])
        nav = []
        if page:
            nav.append(dict(text='Назад', callback_data='sessions:' + str(page-1)))
        if (page+1)*8 < len(keys):
            nav.append(dict(text='Далее', callback_data='sessions:' + str(page+1)))
        if nav:
            buttons.append(nav)
        self.enqueue('Сессии. Выбери кнопкой или /use ID.\n' + '\n'.join(lines),
                     markup=dict(inline_keyboard=buttons))

    def close(self):
        for job, _ in self.jobs.values():
            job.cancel()
        self.pool.shutdown(wait=True, cancel_futures=True)

    def persist(self):
        save(self.state_path, self.state)

    def enqueue(self, text, sid=None, markup=None):
        # Repeat the session label on every chunk, including retried deliveries.
        prefix = self.label(sid) + '\n' if sid else ''
        entries = []
        for i in range(0, len(text), 1800):
            chunk = prefix + text[i:i+1800]
            entries.append(dict(text=chunk, reply_markup=markup) if markup else chunk)
        self.state.setdefault('outbox', []).extend(entries)
        self.persist()

    def refresh(self):
        result = subprocess.run([self.config['meter'], 'refresh'], capture_output=True, timeout=100)
        if result.returncode:
            raise RuntimeError('Не удалось обновить квоту')
        return json.loads(result.stdout)

    def handle(self, update):
        callback = update.get('callback_query')
        if callback:
            message = dict(callback.get('message', {}))
            message['from'] = callback.get('from', {})
            if not authorized(message, self.owner):
                return
            data = callback.get('data', '')
            if data.startswith('use:'):
                self.select_session(data[4:])
            elif data.startswith('sessions:') and data[9:].isdigit():
                self.list_sessions(int(data[9:]))
            try:
                self.telegram.call('answerCallbackQuery', callback_query_id=callback['id'])
            except Exception:
                pass  # Selection is already persisted; an expired callback is harmless.
            return
        message = update.get('message', {})
        if not authorized(message, self.owner):
            return
        text = message.get('text', '').strip()
        if not text:
            self.enqueue('Пока поддерживаются только текстовые сообщения.')
            return
        parts = text.split(maxsplit=1)
        command = parts[0].split('@')[0]
        argument = parts[1] if len(parts) > 1 else ''
        sid = self.state['active_session']
        if command in ('/start', '/help'):
            self.enqueue('/limits — свежие лимиты\n/new [название] — новый диалог\n'
                         '/sessions — список и кнопки выбора\n/use ID — выбрать диалог\n'
                         '/cancel — остановить запрос выбранной сессии\n/status — состояние\n'
                         'Обычный текст отправляется в выбранную сессию. '
                         'Все сессии используют общую рабочую папку: ' + self.config['workspace']
                         + '. Режим: ' + self.config.get('sandbox', 'read-only'))
        elif command == '/limits':
            self.want_limits = True
            self.next_refresh = 0
        elif command == '/sessions':
            self.list_sessions()
        elif command == '/use':
            self.select_session(argument.strip())
        elif command == '/status':
            self.enqueue(('Codex выполняет запрос.' if sid in self.jobs else 'Codex готов к запросу.')
                         + f' Активных запросов: {len(self.jobs)}/{self.max_parallel}.'
                         + '\n' + quota_text(self.snapshot, time.time()), sid=sid)
        elif command == '/cancel':
            if sid in self.jobs:
                self.jobs[sid][0].cancel()
            self.enqueue('Отмена запрошена.' if sid in self.jobs else 'Активного запроса нет.', sid=sid)
        elif command == '/new':
            sid = self.create_session(argument)
            self.enqueue('Создана и выбрана новая сессия. Отправь запрос.', sid=sid)
        elif text.startswith('/'):
            self.enqueue('Неизвестная команда. /help')
        elif sid in self.jobs:
            self.enqueue('Запрос уже выполняется. Дождись ответа или отправь /cancel. '
                         'Для другой задачи: /new название.', sid=sid)
        elif time.time() - message.get('date', 0) > 600:
            self.enqueue('Сообщение старше 10 минут: не запускаю отложенную задачу автоматически. Отправь запрос снова.')
        elif len(self.jobs) >= self.max_parallel:
            self.enqueue('Достигнут предел параллельных запросов. Дождись ответа и отправь запрос снова.', sid=sid)
        else:
            self.sessions[sid]['running'] = True
            self.enqueue('Запрос принят. Для остановки выбери эту сессию и отправь /cancel.', sid=sid)
            job = CodexJob(self.config)
            try:
                future = self.pool.submit(job.run, text, self.sessions[sid].get('thread'))
            except Exception:
                self.sessions[sid]['running'] = False
                self.enqueue('Не удалось запустить запрос. Отправь его снова.', sid=sid)
                return
            self.jobs[sid] = (job, future)

    def tick(self):
        now = time.time()
        for sid, (_, future) in list(self.jobs.items()):
            if not future.done():
                continue
            try:
                thread, answer = future.result()
                self.sessions[sid]['thread'] = thread
            except Exception:
                answer = 'Не удалось запустить Codex. Проверь локальные настройки бота.'
            del self.jobs[sid]
            self.sessions[sid]['running'] = False
            self.enqueue(answer, sid=sid)
        if self.quota_future and self.quota_future.done():
            try:
                self.snapshot = self.quota_future.result()
                self.state['snapshot'] = self.snapshot
                messages = reminders(self.snapshot, self.state, now, self.config.get('reminder_hours', [48, 24, 6]))
                # Persist dedupe and pending messages together, including failed sends.
                for message in messages:
                    self.state.setdefault('outbox', []).append(message)
                self.persist()
                self.next_refresh = now + 60
            except Exception:
                self.next_refresh = now + 300
                if self.want_limits:
                    self.enqueue('Обновить лимиты не удалось. Ниже последнее измерение.')
            self.quota_future = None
            if self.want_limits:
                self.enqueue(quota_text(self.snapshot, now))
                self.want_limits = False
        if not self.quota_future and now >= self.next_refresh:
            self.quota_future = self.pool.submit(self.refresh)
        if self.state.get('outbox'):
            entry = self.state['outbox'][0]
            payload = dict(text=entry) if isinstance(entry, str) else entry
            self.telegram.call('sendMessage', chat_id=self.owner, **payload)
            self.state['outbox'].pop(0)
            self.persist()

    def run(self):
        while True:
            try:
                self.tick()
                updates = self.telegram.call('getUpdates', offset=self.state.get('offset', 0),
                                             timeout=2, allowed_updates=['message', 'callback_query'])
                for update in updates:
                    # At most once model execution across restarts, even if the reply fails.
                    self.state['offset'] = update['update_id'] + 1
                    self.persist()
                    self.handle(update)
            except Exception:
                print('Временный сбой бота; повтор через 10 секунд.', flush=True)
                time.sleep(10)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=ROOT)
    args = parser.parse_args()
    directory = args.directory.expanduser().resolve()
    config = json.loads((directory / 'config.json').read_text())
    if not isinstance(config.get('owner_id'), int) or config['owner_id'] <= 0:
        raise SystemExit('Нужен положительный owner_id личного Telegram-аккаунта.')
    if config.get('sandbox', 'read-only') not in ('read-only', 'workspace-write'):
        raise SystemExit('Допустимы read-only и workspace-write.')
    with open(directory / 'bot.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        bot = Bot(config, directory)
        def shutdown(signum, frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, shutdown)
        try:
            bot.run()
        except KeyboardInterrupt:
            pass
        finally:
            bot.close()


if __name__ == '__main__':
    main()
