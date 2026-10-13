#!/usr/bin/env python3
"""Registra transições de funcionalidades e regenera o painel de acompanhamento."""
import argparse
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Progress' / 'progress.json'

def render(data):
    template = (ROOT / 'Progress' / 'template.html').read_text()
    payload = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
    (ROOT / 'Progress' / 'index.html').write_text(template.replace('/*PROGRESS_DATA*/', payload))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'done', 'pending', 'blocked', 'render'])
    parser.add_argument('feature', nargs='?')
    parser.add_argument('--note', default='')
    args = parser.parse_args()
    data = json.loads(DATA.read_text())
    if args.action != 'render':
        feature = next((f for f in data['features'] if f['id'] == args.feature), None)
        if feature is None:
            parser.error('Funcionalidade não encontrada.')
        timestamp = datetime.now(ZoneInfo('America/Sao_Paulo')).isoformat(timespec='seconds')
        feature['status'] = {'start':'active', 'done':'done', 'pending':'pending', 'blocked':'blocked'}[args.action]
        feature['note'] = args.note
        feature['updatedAt'] = timestamp
        data['updatedAt'] = timestamp
        data['events'].insert(0, {'at':timestamp, 'feature':feature['id'], 'title':feature['title'], 'action':args.action, 'note':args.note})
        DATA.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    render(data)
    print(f'Painel atualizado: {ROOT / "Progress" / "index.html"}')

if __name__ == '__main__':
    main()
