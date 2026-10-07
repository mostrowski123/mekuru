#!/usr/bin/env python3
"""Capture the raw store screenshots on an Android emulator, in every UI language.

The emulator must already hold the screenshot library (see store_listing/README.md):
dictionaries, the Black Jack CBZ with OCR on page 28, the Aozora books with
羅生門 open at its first page of text, saved words, seeded reading stats, a
collection, and AnkiDroid with Mekuru's Anki field mapping set. Drives the app over adb by on-screen labels (uiautomator), switches
the UI language through shared preferences, and writes
build/store_images/raw/<device>/<lang>/<nn>.png for tools/compose_store_images.py.

  python3 tools/capture_android_store_shots.py phone en es id zh
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'moe.matthew.mekuru'
PREFS = 'shared_prefs/FlutterSharedPreferences.xml'
LANGS = {'en': 'en', 'es': 'es', 'id': 'id', 'zh': 'zh_Hans'}
ARB = {'en': 'app_en.arb', 'es': 'app_es.arb', 'id': 'app_id.arb', 'zh': 'app_zh_Hans.arb'}

# Points on the page itself, which no label names: the word 大人 in the
# speech bubble on page 28 of Black Jack, and 待っていた in 羅生門's first column.
DEVICES = {
    'phone': {'manga_word': (312, 930), 'novel_word': (905, 1520)},
    'tablet': {'manga_word': (428, 885), 'novel_word': (1462, 1222)},
}


def adb(*args: str, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(['adb', *args], capture_output=True, **kw)


def dump() -> list[tuple[str, tuple[int, int, int, int]]]:
    for _ in range(8):
        adb('shell', 'rm', '-f', '/sdcard/ui.xml')
        r = adb('shell', 'uiautomator', 'dump', '/sdcard/ui.xml', text=True)
        if 'ERROR' not in r.stdout + r.stderr:
            break
        time.sleep(1)
    xml = adb('shell', 'cat', '/sdcard/ui.xml', text=True).stdout
    items = []
    for node in re.findall(r'<node [^>]*>', xml):
        label = (re.search(r' text="([^"]*)"', node) or [None, ''])[1] or (
            re.search(r' content-desc="([^"]*)"', node) or [None, ''])[1]
        box = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
        if label and box:
            items.append((label.replace('&#10;', ' | '), tuple(map(int, box.groups()))))
    return items


def tap_xy(x: int, y: int, wait: float = 1.5) -> None:
    adb('shell', 'input', 'tap', str(x), str(y))
    time.sleep(wait)


def tap(match, wait: float = 1.5, timeout: float = 15) -> None:
    """Taps the first element whose label satisfies [match] (a callable or a prefix)."""
    pred = match if callable(match) else (lambda label: label.startswith(match))
    end = time.time() + timeout
    while time.time() < end:
        for label, (x1, y1, x2, y2) in dump():
            if pred(label):
                tap_xy((x1 + x2) // 2, (y1 + y2) // 2, wait)
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


def back(wait: float = 1.5) -> None:
    adb('shell', 'input', 'keyevent', 'BACK')
    time.sleep(wait)


def set_language(lang: str) -> None:
    adb('shell', 'am', 'force-stop', PACKAGE)
    xml = adb('shell', 'run-as', PACKAGE, 'cat', PREFS, text=True).stdout
    entry = f'<string name="flutter.app.language">{LANGS[lang]}</string>'
    if 'flutter.app.language' in xml:
        xml = re.sub(r'<string name="flutter.app.language">[^<]*</string>', entry, xml)
    else:
        xml = xml.replace('</map>', f'    {entry}\n</map>')
    subprocess.run(['adb', 'exec-in', 'run-as', PACKAGE, 'sh', '-c', f'cat > {PREFS}'], input=xml.encode(), check=True)
    adb('shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(8)


def demo_status_bar() -> None:
    adb('shell', 'settings', 'put', 'global', 'sysui_demo_allowed', '1')
    for extra in (['enter'], ['clock', '-e', 'hhmm', '0941'], ['battery', '-e', 'level', '100', '-e', 'plugged', 'false'],
                  ['network', '-e', 'wifi', 'show', '-e', 'level', '4'], ['network', '-e', 'mobile', 'hide'],
                  ['notifications', '-e', 'visible', 'false']):
        cmd = ['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', extra[0], *extra[1:]]
        adb(*cmd)


def main() -> None:
    device, langs = sys.argv[1], sys.argv[2:] or list(LANGS)
    cfg = DEVICES[device]
    demo_status_bar()
    for lang in langs:
        l10n = json.loads((ROOT / 'lib' / 'l10n' / ARB[lang]).read_text(encoding='utf-8'))
        out = ROOT / 'build' / 'store_images' / 'raw' / device / lang
        out.mkdir(parents=True, exist_ok=True)

        def shot(nn: str, settle: float = 1.5) -> None:
            time.sleep(settle)
            (out / f'{nn}.png').write_bytes(adb('exec-out', 'screencap', '-p').stdout)
            print(f'{device}/{lang}/{nn}', flush=True)

        set_language(lang)
        tab = lambda key: (lambda label: label.startswith(l10n[key] + ' |'))  # noqa: E731
        if not wait_for(tab('navLibrary')):
            raise RuntimeError('library did not open')
        shot('08')

        tap(lambda label: label.endswith('ブラックジャックによろしく 1') and '|' not in label, wait=6)
        tap_xy(*cfg['manga_word'], wait=3)
        shot('01')
        back()
        back(2)

        tap(lambda label: label.endswith('羅生門') and '|' not in label, wait=7)
        shot('02', settle=2)
        tap_xy(*cfg['novel_word'], wait=3)
        shot('03')
        tap(l10n['lookupTabSentence'], wait=2)
        # Standard translation into this language may need its model first.
        if wait_for(l10n['commonDownload'], timeout=4):
            tap(l10n['commonDownload'], wait=2)
        time.sleep(8)
        shot('04')
        # The Add to Anki screen, from the same lookup. AnkiDroid must be
        # installed and Mekuru's field mapping set; the card is not added.
        tap(l10n['lookupTabDictionary'], wait=2)
        tap(lambda label: label == l10n['dictionarySendToAnkiTooltip'].replace('{app}', 'AnkiDroid'), wait=4)
        shot('05')
        back()
        back()
        back(2)

        tap(tab('navYou'), wait=2)
        tap(l10n['freeBooksTitle'], wait=3)
        tap(l10n['freeBooksTabAozora'], wait=4)
        # Show the whole catalogue by popularity, not a level filter left from before.
        if wait_for(l10n['freeBooksClearFilters'], timeout=3):
            tap(l10n['freeBooksClearFilters'], wait=3)
        shot('06')
        back(2)
        tap(l10n['statsScreenTitle'], wait=3)
        shot('07')
        back(2)
        tap(tab('navLibrary'), wait=2)


if __name__ == '__main__':
    main()
