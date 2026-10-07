#!/usr/bin/env python3
"""Replace the Google Play store images (never the listing text).

Reads tools/compose_store_images.py's output, build/store_images/play/<lang>/,
and for each Play locale replaces the phone, 7-inch and 10-inch tablet
screenshots and the feature graphic. Without flags it only checks the files.

  python3 tools/publish_play_store_images.py              # check sizes and counts
  python3 tools/publish_play_store_images.py --commit     # upload and commit one edit

Needs tools/requirements-play-store.txt and the service account key at
~/.config/google-play-mcp/service-account.json (or --key). Nothing is public
until the edit is committed; Google then reviews the listing change.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from urllib.parse import quote

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'moe.matthew.mekuru'
API = 'https://androidpublisher.googleapis.com/androidpublisher/v3'
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3'
KEY = Path.home() / '.config' / 'google-play-mcp' / 'service-account.json'

# Play locale -> caption language of the image set it gets.
LOCALES = {'en-US': 'en', 'es-ES': 'es', 'es-US': 'es', 'id': 'id', 'ja-JP': 'ja', 'zh-CN': 'zh'}
# Play image type -> (folder, size, how many images).
TYPES = {
    'phoneScreenshots': ('phone', (1080, 1920), range(2, 9)),
    'sevenInchScreenshots': ('tablet-7', (1200, 1920), range(1, 9)),
    'tenInchScreenshots': ('tablet-10', (1600, 2560), range(1, 9)),
    'featureGraphic': ('feature', (1024, 500), range(1, 2)),
}


def images(lang: str) -> dict[str, list[Path]]:
    """The files for each image type, after checking size, colour mode and count."""
    found = {}
    for image_type, (folder, size, counts) in TYPES.items():
        paths = sorted((ROOT / 'build' / 'store_images' / 'play' / lang / folder).glob('*.png'))
        if len(paths) not in counts:
            raise SystemExit(f'{lang}/{folder}: {len(paths)} images, expected {counts.start}-{counts.stop - 1}')
        for path in paths:
            with Image.open(path) as im:
                if im.size != size or im.mode != 'RGB':
                    raise SystemExit(f'{path}: {im.size} {im.mode}, expected {size} RGB')
        found[image_type] = paths
    return found


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--commit', action='store_true', help='upload and commit the edit')
    parser.add_argument('--locales', default=','.join(LOCALES))
    parser.add_argument('--key', type=Path, default=KEY)
    args = parser.parse_args()

    plan = {locale: images(LOCALES[locale]) for locale in args.locales.split(',')}
    for locale, found in plan.items():
        print(locale, ', '.join(f'{t}: {len(p)}' for t, p in found.items()))
    if not args.commit:
        print('Checked only. Pass --commit to upload.')
        return

    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_file(
        args.key, scopes=['https://www.googleapis.com/auth/androidpublisher'])
    session = AuthorizedSession(credentials)

    def call(method: str, url: str, **kwargs) -> dict:
        response = session.request(method, url, timeout=180, **kwargs)
        if not response.ok:
            raise SystemExit(f'{method} {url}: {response.status_code} {response.text}')
        return response.json() if response.content else {}

    edit = call('POST', f'{API}/applications/{PACKAGE}/edits', json={})['id']
    for locale, found in plan.items():
        for image_type, paths in found.items():
            path = f'/applications/{PACKAGE}/edits/{edit}/listings/{quote(locale, safe="")}/{image_type}'
            call('DELETE', API + path)
            for file in paths:
                call('POST', f'{UPLOAD}{path}?uploadType=media', data=file.read_bytes(),
                     headers={'Content-Type': 'image/png'})
            print(f'{locale} {image_type}: {len(paths)} uploaded')
    print('commit:', call('POST', f'{API}/applications/{PACKAGE}/edits/{edit}:commit'))


if __name__ == '__main__':
    main()
