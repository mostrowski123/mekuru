#!/usr/bin/env python3
"""Capture the raw App Store screenshots on an iOS simulator, in every UI language.

Same states as tools/capture_android_store_shots.py, minus the sentence
translation (the simulator has no Apple Translation). The simulator must hold
the screenshot library (see store_listing/README.md). Drives the app with AXe
(`brew install cameroncooke/axe/axe`) by accessibility labels, switches the UI
language through the app's user defaults, and writes
build/store_images/raw/<device>/<lang>/<nn>.png.

  python3 tools/capture_ios_store_shots.py iphone <udid> en es id zh
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = 'moe.matthew.mekuru'
LANGS = {'en': 'en', 'es': 'es', 'id': 'id', 'zh': 'zh_Hans'}
ARB = {'en': 'app_en.arb', 'es': 'app_es.arb', 'id': 'app_id.arb', 'zh': 'app_zh_Hans.arb'}
# Flutter's own back-button label (MaterialLocalizations), not in the app's .arb files.
BACK = {'en': 'Back', 'es': 'Atrás', 'id': 'Kembali', 'zh': '返回'}

# Points (not pixels) that no label names: 大人 in the speech bubble on page 28
# of Black Jack, and 待っていた in 羅生門's first column.
DEVICES = {
    'iphone': {'manga_word': (122, 357), 'novel_word': (370, 648)},
    'ipad': {'manga_word': (303, 445), 'novel_word': (965, 610)},
}

UDID = ''


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(list(args), capture_output=True, text=True)


def dump() -> list[tuple[str, tuple[float, float, float, float]]]:
    try:
        tree = json.loads(run('axe', 'describe-ui', '--udid', UDID).stdout)
    except json.JSONDecodeError:
        return []
    items = []

    def walk(node: dict) -> None:
        label, value, frame = node.get('AXLabel') or '', node.get('AXValue') or '', node.get('frame')
        text = f'{label} | {value}' if label and value else label or value
        if text and frame:
            # AXe returns decomposed kana (ブ as フ + ゛); compare composed.
            items.append((unicodedata.normalize('NFC', text.replace('\n', ' | ')),
                          (frame['x'], frame['y'], frame['x'] + frame['width'], frame['y'] + frame['height'])))
        for child in node.get('children') or []:
            walk(child)

    for node in tree if isinstance(tree, list) else [tree]:
        walk(node)
    return items


def tap_xy(x: float, y: float, wait: float = 1.5) -> None:
    # The default "simulator" tap style stops reaching the app after a while.
    run('axe', 'tap', '-x', str(round(x)), '-y', str(round(y)), '--tap-style', 'physical', '--udid', UDID)
    time.sleep(wait)


def tap(match, wait: float = 1.5, timeout: float = 15) -> None:
    pred = match if callable(match) else (lambda label: label == match or label.startswith(match))
    end = time.time() + timeout
    while time.time() < end:
        for label, (x1, y1, x2, y2) in dump():
            if pred(label) and y2 > y1:
                tap_xy((x1 + x2) / 2, (y1 + y2) / 2, wait)
                return
        time.sleep(1)
    raise RuntimeError(f'not on screen: {match}')


def wait_for(match, timeout: float = 30) -> bool:
    pred = match if callable(match) else (lambda label: label.startswith(match))
    end = time.time() + timeout
    while time.time() < end:
        if any(pred(label) for label, _ in dump()):
            return True
        time.sleep(1)
    return False


def set_language(lang: str) -> None:
    run('xcrun', 'simctl', 'terminate', UDID, BUNDLE)
    # The app's defaults live in its own container, not in the simulator's global domain.
    container = run('xcrun', 'simctl', 'get_app_container', UDID, BUNDLE, 'data').stdout.strip()
    domain = f'{container}/Library/Preferences/{BUNDLE}'
    run('xcrun', 'simctl', 'spawn', UDID, 'defaults', 'write', domain, 'flutter.app.language', '-string', LANGS[lang])
    run('xcrun', 'simctl', 'launch', UDID, BUNDLE)
    time.sleep(10)


def main() -> None:
    global UDID
    device, UDID, langs = sys.argv[1], sys.argv[2], sys.argv[3:] or list(LANGS)
    cfg = DEVICES[device]
    run('xcrun', 'simctl', 'status_bar', UDID, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active',
        '--wifiBars', '3', '--cellularMode', 'notSupported', '--batteryState', 'charged', '--batteryLevel', '100')
    for lang in langs:
        l10n = json.loads((ROOT / 'lib' / 'l10n' / ARB[lang]).read_text(encoding='utf-8'))
        out = ROOT / 'build' / 'store_images' / 'raw' / device / lang
        out.mkdir(parents=True, exist_ok=True)

        def shot(nn: str, settle: float = 1.5) -> None:
            time.sleep(settle)
            run('xcrun', 'simctl', 'io', UDID, 'screenshot', str(out / f'{nn}.png'))
            print(f'{device}/{lang}/{nn}', flush=True)

        set_language(lang)
        if not wait_for(l10n['navLibrary']):
            raise RuntimeError('library did not open')
        shot('08')

        tap(lambda label: label.startswith('ブラックジャックによろしく 1 |'), wait=6)
        tap_xy(*cfg['manga_word'], wait=3)
        shot('01')
        set_language(lang)   # a relaunch is the surest way back to the library

        tap(lambda label: label.startswith('羅生門 |'), wait=8)
        shot('02', settle=2)
        tap_xy(*cfg['novel_word'], wait=3)
        shot('03')
        set_language(lang)

        tap(l10n['navVocabulary'], wait=2)
        tap(lambda label: label.startswith('大人 |'), wait=1.5)
        shot('05')

        tap(l10n['navYou'], wait=2)
        tap(l10n['freeBooksTitle'], wait=3)
        tap(l10n['freeBooksTabAozora'], wait=4)
        if wait_for(l10n['freeBooksClearFilters'], timeout=3):
            tap(l10n['freeBooksClearFilters'], wait=3)
        shot('06')
        tap(lambda label: label in (BACK[lang], l10n.get('commonBack')), wait=2)
        tap(l10n['statsScreenTitle'], wait=3)
        shot('07')
        tap(lambda label: label in (BACK[lang], l10n.get('commonBack')), wait=2)
        tap(l10n['navLibrary'], wait=2)


if __name__ == '__main__':
    main()
