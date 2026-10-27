#!/usr/bin/env python3
"""Interactive local setup; token never appears in arguments or logs."""
import argparse
import getpass
import json
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import time

from bot import ROOT, Telegram, save
from control import DEFAULT_PERMISSIONS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--codex', type=Path, required=True)
    parser.add_argument('--meter', type=Path, required=True)
    parser.add_argument('--sandbox', choices=['read-only', 'workspace-write'], default='read-only')
    parser.add_argument('--allow-codex', action='store_true', help='Разрешить выполнение запросов Codex и отправку ответов')
    args = parser.parse_args()
    for path in [args.workspace, args.codex, args.meter]:
        if not path.expanduser().exists():
            raise SystemExit('Не найден путь: ' + str(path))
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    label = 'local.codex-meter.telegram'
    domain = 'gui/' + str(os.getuid())
    # Setup must never compete with the existing long poller.
    subprocess.run(['launchctl', 'bootout', domain + '/' + label], capture_output=True)
    token = getpass.getpass('Токен нового бота от BotFather (ввод скрыт): ').strip()
    telegram = Telegram(token)
    identity = telegram.call('getMe')
    nonce = secrets.token_urlsafe(24)
    print('Открой ссылку своим Telegram-аккаунтом и нажми Start:')
    print('https://t.me/' + identity['username'] + '?start=' + nonce)
    deadline, offset, owner = time.time() + 600, 0, None
    while time.time() < deadline and owner is None:
        for update in telegram.call('getUpdates', offset=offset, timeout=20, allowed_updates=['message']):
            offset = update['update_id'] + 1
            message = update.get('message', {})
            user = message.get('from', {})
            chat = message.get('chat', {})
            if (message.get('text') == '/start ' + nonce and chat.get('type') == 'private'
                    and user.get('id') == chat.get('id') and not user.get('is_bot')):
                owner = user['id']
    if owner is None:
        raise SystemExit('Время привязки истекло. Запусти настройку снова.')
    fd = os.open(ROOT / 'token', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(token)
    os.chmod(ROOT / 'token', 0o600)
    config = dict(owner_id=owner, workspace=str(args.workspace.expanduser().resolve()),
                  codex=str(args.codex.expanduser().resolve()), meter=str(args.meter.expanduser().resolve()),
                  sandbox=args.sandbox, reminder_hours=[48, 24, 6], bot_username=identity['username'],
                  permissions=dict(DEFAULT_PERMISSIONS, codex=args.allow_codex))
    save(ROOT / 'config.json', config)
    # Changing bot/owner must not expose old replies or resume another conversation.
    save(ROOT / 'state.json', {'offset': offset, 'outbox': [dict(text='Codex Meter подключён. /limits показывает остаток. Запросы Codex '+('разрешены.' if args.allow_codex else 'выключены.'), category='service')]})
    shutil.copyfile(Path(__file__).with_name('bot.py'), ROOT / 'bot.py')
    os.chmod(ROOT / 'bot.py', 0o600)
    plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    plist.parent.mkdir(parents=True, exist_ok=True)
    payload = dict(Label=label, ProgramArguments=[sys.executable, str(ROOT / 'bot.py')],
                   RunAtLoad=True, KeepAlive=True, ThrottleInterval=30,
                   StandardOutPath=str(ROOT / 'service.log'), StandardErrorPath=str(ROOT / 'service.log'),
                   EnvironmentVariables={'PATH': os.environ.get('PATH', '/usr/bin:/bin')})
    with plist.open('wb') as stream:
        plistlib.dump(payload, stream)
    os.chmod(plist, 0o600)
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    print('Бот привязан к твоему аккаунту и запущен. Открой чат и отправь /limits. Разрешения доступны в настройках приложения.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, KeyboardInterrupt) as exc:
        raise SystemExit(str(exc) or 'Настройка прервана.') from None
