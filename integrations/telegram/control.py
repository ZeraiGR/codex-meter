#!/usr/bin/env python3
"""Local settings bridge. Requests (including tokens) arrive only over stdin."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import time
import tempfile

from bot import ROOT, Telegram, save

LABEL = 'local.codex-meter.telegram'
DEFAULT_PERMISSIONS = dict(limits=True, reminders=True, window_changes=True, codex=False)


class Controller:
    def __init__(self, directory=ROOT, agents=None, telegram=Telegram, launch=None):
        self.root = Path(directory)
        self.agents = Path(agents) if agents else Path.home() / 'Library/LaunchAgents'
        self.telegram = telegram
        self.launch = launch or self.launchctl
        self.domain = 'gui/' + str(os.getuid())

    @staticmethod
    def launchctl(*args):
        return subprocess.run(['/bin/launchctl', *args], capture_output=True, timeout=20).returncode

    def read(self, name, default=None):
        path = self.root / name
        return json.loads(path.read_text()) if path.exists() else (default or {})

    def running(self):
        return self.launch('print', self.domain + '/' + LABEL) == 0

    def busy(self):
        state = self.read('state.json')
        return bool(state.get('running') or any(s.get('running') for s in state.get('sessions', {}).values()))

    def status(self):
        config = self.read('config.json')
        connected = bool(config.get('owner_id') and (self.root / 'token').exists())
        pending = self.read('pairing.json')
        # Legacy installations retain their explicitly enabled Codex access.
        permissions = config.get('permissions', dict.fromkeys(DEFAULT_PERMISSIONS, True)) if connected else DEFAULT_PERMISSIONS.copy()
        return dict(connected=connected, running=self.running() if connected else False,
                    busy=self.busy() if connected else False,
                    username=config.get('bot_username', ''), owner_id=config.get('owner_id', 0),
                    workspace=config.get('workspace', ''), codex=config.get('codex', ''),
                    sandbox=config.get('sandbox', 'read-only'), permissions=permissions,
                    max_parallel=config.get('max_parallel', 3), reminder_hours=config.get('reminder_hours', [48, 24, 6]),
                    tunnel_port=self.read('network.json').get('tunnel_port', 0),
                    pending_url=pending.get('url', '') if pending.get('expires', 0) > time.time() else '')

    def options(self, request):
        permissions = request.get('permissions', DEFAULT_PERMISSIONS)
        if set(permissions) != set(DEFAULT_PERMISSIONS) or any(type(v) is not bool for v in permissions.values()):
            raise RuntimeError('Выберите разрешённые категории сообщений.')
        sandbox = request.get('sandbox', 'read-only')
        if sandbox not in ('read-only', 'workspace-write'):
            raise RuntimeError('Выберите режим доступа Codex.')
        workspace = str(Path(request.get('workspace') or str(Path.home())).expanduser().resolve())
        codex = request.get('codex', '')
        if permissions['codex'] and (not Path(workspace).is_dir() or not os.access(codex, os.X_OK) or not Path(codex).is_file()):
            raise RuntimeError('Для запросов Codex выберите папку проекта и исполняемый файл Codex.')
        meter = request.get('meter', '')
        if not Path(meter).is_file() or not os.access(meter, os.X_OK):
            raise RuntimeError('Не найдено установленное приложение Codex Meter.')
        parallel = request.get('max_parallel', 3)
        hours = request.get('reminder_hours', [48, 24, 6])
        if type(parallel) is not int or not 1 <= parallel <= 8:
            raise RuntimeError('Число параллельных запросов должно быть от 1 до 8.')
        if not isinstance(hours, list) or (permissions['reminders'] and not hours) or any(type(h) is not int or not 1 <= h <= 168 for h in hours):
            raise RuntimeError('Время напоминаний должно быть от 1 до 168 часов.')
        port = request.get('tunnel_port', 0)
        if type(port) is not int or not 0 <= port <= 65535:
            raise RuntimeError('Порт туннеля должен быть от 1 до 65535, либо 0 для прямого доступа.')
        return dict(workspace=workspace, codex=codex, meter=meter, sandbox=sandbox,
                    permissions=permissions, max_parallel=parallel, reminder_hours=sorted(set(hours), reverse=True)), port

    def stop(self):
        if self.running() and self.launch('bootout', self.domain + '/' + LABEL) != 0:
            raise RuntimeError('Не удалось остановить службу Telegram. Повторите попытку.')
        (self.agents / (LABEL + '.plist')).unlink(missing_ok=True)

    def start(self):
        if not self.status()['connected']:
            raise RuntimeError('Сначала подключите своего бота.')
        if self.running():
            return
        shutil.copyfile(Path(__file__).with_name('bot.py'), self.root / 'bot.py')
        os.chmod(self.root / 'bot.py', 0o600)
        self.agents.mkdir(parents=True, exist_ok=True)
        payload = dict(Label=LABEL, ProgramArguments=[sys.executable, str(self.root / 'bot.py'), '--directory', str(self.root)],
                       RunAtLoad=True, KeepAlive=True, ThrottleInterval=30,
                       StandardOutPath=str(self.root / 'service.log'), StandardErrorPath=str(self.root / 'service.log'),
                       EnvironmentVariables={'PATH': os.environ.get('PATH', '/usr/bin:/bin')})
        path = self.agents / (LABEL + '.plist')
        path.write_bytes(plistlib.dumps(payload));path.chmod(0o600)
        if self.launch('bootstrap', self.domain, str(path)) != 0:
            raise RuntimeError('Настройки сохранены, но служба не запущена. Нажмите «Включить».')

    def network(self, directory, port):
        save(directory / 'network.json', {'tunnel_port': port} if port else {})

    def begin(self, request):
        request = dict(request)
        request['permissions'] = dict(request.get('permissions', DEFAULT_PERMISSIONS), codex=False)
        options, port = self.options(request)
        token = request.get('token', '').strip()
        if not token or len(token) > 256 or any(c.isspace() for c in token):
            raise RuntimeError('Введите токен, полученный от BotFather.')
        if (self.root / 'token').exists() and secrets.compare_digest(token, (self.root / 'token').read_text().strip()):
            raise RuntimeError('Этот бот уже подключён. Измените разрешения или отключите его перед новой привязкой.')
        staging = self.root / 'pending'
        staging.mkdir(exist_ok=True, mode=0o700)
        self.network(staging, port)
        api = self.telegram(token, staging)
        identity = api.call('getMe')
        if api.call('getWebhookInfo').get('url'):
            raise RuntimeError('У этого бота настроен webhook. Создайте отдельного бота через BotFather.')
        nonce = secrets.token_urlsafe(24)
        save(self.root / 'pairing.json', dict(token=token, nonce=nonce, expires=time.time()+600,
             offset=0, options=options, port=port, username=identity['username'],
             url='https://t.me/' + identity['username'] + '?start=' + nonce))

    def pair(self):
        pending = self.read('pairing.json')
        if pending.get('expires', 0) <= time.time():
            self.cancel()
            raise RuntimeError('Ссылка истекла. Подключите бота заново.')
        api = self.telegram(pending['token'], self.root / 'pending')
        for update in api.call('getUpdates', offset=pending['offset'], timeout=0, allowed_updates=['message']):
            pending['offset'] = update['update_id'] + 1
            msg = update.get('message', {});user = msg.get('from', {});chat = msg.get('chat', {})
            if (msg.get('text') == '/start ' + pending['nonce'] and chat.get('type') == 'private'
                    and type(user.get('id')) is int and user['id'] > 0 and user['id'] == chat.get('id') and not user.get('is_bot')):
                if self.running() and self.busy():
                    raise RuntimeError('В прежнем боте выполняются запросы. Дождитесь их завершения или остановите модуль.')
                # Only explicit, successful pairing replaces the private identity.
                self.stop()
                names = ('config.json', 'token', 'state.json', 'network.json')
                before = {name: (self.root/name).read_bytes() if (self.root/name).exists() else None for name in names}
                self.archive()
                try:
                    config = dict(pending['options'], owner_id=user['id'], bot_username=pending['username'])
                    save(self.root / 'config.json', config)
                    self.write_bytes(self.root / 'token', pending['token'].encode())
                    self.network(self.root, pending['port'])
                    save(self.root / 'state.json', dict(offset=pending['offset'], outbox=[]))
                except Exception:
                    self.restore(before)
                    raise RuntimeError('Не удалось сохранить новую привязку. Прежние настройки восстановлены; включите модуль снова.') from None
                self.cancel()
                self.start()
                return
        save(self.root / 'pairing.json', pending)

    def cancel(self):
        (self.root / 'pairing.json').unlink(missing_ok=True)
        shutil.rmtree(self.root / 'pending', ignore_errors=True)

    @staticmethod
    def write_bytes(path, data):
        fd, temporary = tempfile.mkstemp(dir=path.parent)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data);stream.flush();os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):os.unlink(temporary)

    def restore(self, before):
        for name, data in before.items():
            if data is None:(self.root/name).unlink(missing_ok=True)
            else:self.write_bytes(self.root/name, data)

    def archive(self):
        archive = self.root / 'previous';archive.mkdir(exist_ok=True, mode=0o700)
        for name in ('config.json', 'state.json'):
            if (self.root/name).exists():
                shutil.copy2(self.root/name, archive/name);(archive/name).chmod(0o600)

    def configure(self, request):
        options, port = self.options(request)
        config = self.read('config.json')
        if not self.status()['connected']:
            raise RuntimeError('Сначала подключите своего бота.')
        if self.running() and self.busy():
            raise RuntimeError('Дождитесь завершения запросов или остановите модуль перед изменением настроек.')
        state = self.read('state.json')
        has_history = state.get('thread') or any(s.get('thread') for s in state.get('sessions', {}).values())
        if options['workspace'] != config.get('workspace') and has_history:
            raise RuntimeError('Для другой рабочей папки отключите привязку и подключите бота заново, чтобы не смешивать диалоги проектов.')
        running = self.running()
        self.stop()
        before = {name: (self.root/name).read_bytes() if (self.root/name).exists() else None for name in ('config.json','network.json')}
        config.update(options)
        try:
            save(self.root / 'config.json', config);self.network(self.root, port)
        except Exception:
            self.restore(before)
            raise RuntimeError('Не удалось сохранить настройки. Прежние значения восстановлены; включите модуль снова.') from None
        if running:self.start()

    def dispatch(self, request):
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700);self.root.chmod(0o700)
        action = request.get('action')
        if action == 'begin':self.begin(request)
        elif action == 'pair':self.pair()
        elif action == 'cancel':self.cancel()
        elif action == 'save':self.configure(request)
        elif action == 'start':self.start()
        elif action == 'stop':self.stop()
        elif action == 'disconnect':
            self.stop();self.cancel()
            # Keep conversations privately for recovery, never reuse on a new pairing.
            self.archive()
            for name in ('config.json', 'token', 'state.json'):
                (self.root / name).unlink(missing_ok=True)
        elif action != 'status':raise RuntimeError('Неизвестное действие Telegram.')
        return self.status()


def main():
    parser = argparse.ArgumentParser();parser.add_argument('--directory', type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.directory;root.mkdir(parents=True, exist_ok=True, mode=0o700);root.chmod(0o700)
    try:
        with (root / 'settings.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = Controller(root).dispatch(json.load(sys.stdin))
        print(json.dumps(result, ensure_ascii=False))
    except RuntimeError as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False))
    except Exception:
        print(json.dumps({'error': 'Не удалось применить настройки Telegram. Проверьте пути и повторите попытку.'}, ensure_ascii=False))


if __name__ == '__main__':main()
