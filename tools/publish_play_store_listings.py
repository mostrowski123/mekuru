#!/usr/bin/env python3
"""Validate, diff, and explicitly publish Mekuru Google Play listings."""

from __future__ import annotations

import argparse
import difflib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final
from urllib.parse import quote

from PIL import Image


PACKAGE_NAME: Final = "moe.matthew.mekuru"
API_ROOT: Final = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD_ROOT: Final = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
SCOPES: Final = ("https://www.googleapis.com/auth/androidpublisher",)
FIELD_LIMITS: Final = {"title": 30, "shortDescription": 80, "fullDescription": 4000}
LOCALE_SOURCES: Final = {
    "en-US": "en-US.md",
    "es-ES": "es.md",
    "es-US": "es.md",
    "id": "id.md",
    "zh-CN": "zh-CN.md",
}
DEFAULT_LOCALES: Final = ("es-ES", "es-US", "id", "zh-CN")
SCREENSHOT_TYPES: Final = {
    "phone": "phoneScreenshots",
    "7-inch": "sevenInchScreenshots",
    "10-inch": "tenInchScreenshots",
}


@dataclass(frozen=True)
class Listing:
    locale: str
    title: str
    short_description: str
    full_description: str

    def as_api_payload(self) -> dict[str, str]:
        return {
            "language": self.locale,
            "title": self.title,
            "shortDescription": self.short_description,
            "fullDescription": self.full_description,
        }


def parse_listing(path: Path, locale: str) -> Listing:
    text = path.read_text(encoding="utf-8")
    sections: dict[str, str] = {}
    current: str | None = None
    lines: list[str] = []

    def flush() -> None:
        nonlocal lines
        if current is not None:
            sections[current] = "\n".join(lines).strip()
        lines = []

    for line in text.splitlines():
        if line.startswith("## Title"):
            flush()
            current = "title"
        elif line.startswith("## Short description"):
            flush()
            current = "shortDescription"
        elif line.startswith("## Full description"):
            flush()
            current = "fullDescription"
        elif current is not None:
            lines.append(line)
    flush()

    missing = set(FIELD_LIMITS) - sections.keys()
    if missing:
        raise ValueError(f"{path} is missing sections: {', '.join(sorted(missing))}")
    listing = Listing(
        locale=locale,
        title=sections["title"],
        short_description=sections["shortDescription"],
        full_description=sections["fullDescription"],
    )
    validate_listing(listing, path)
    return listing


def validate_listing(listing: Listing, path: Path) -> None:
    payload = listing.as_api_payload()
    for field, limit in FIELD_LIMITS.items():
        value = payload[field]
        if not value:
            raise ValueError(f"{path}: {field} is empty")
        if len(value) > limit:
            raise ValueError(f"{path}: {field} has {len(value)} characters; limit is {limit}")


def screenshot_dir(project_root: Path, locale: str, device_class: str) -> Path:
    source_locale = "es-ES" if locale == "es-US" else locale
    if source_locale == "en-US" and device_class == "phone":
        return project_root / "assets" / "play_store" / "final"
    return (
        project_root
        / "assets"
        / "play_store"
        / "final"
        / source_locale
        / device_class
    )


def validate_screenshots(directory: Path, expected_size: tuple[int, int]) -> list[Path]:
    paths = sorted(path for path in directory.glob("*.png") if path.name != "contact-sheet.png")
    if len(paths) != 6:
        raise ValueError(f"{directory} must contain exactly 6 screenshots; found {len(paths)}")
    for path in paths:
        with Image.open(path) as image:
            if image.size != expected_size:
                raise ValueError(f"{path} has size {image.size}; expected {expected_size}")
            if image.mode != "RGB":
                raise ValueError(f"{path} has mode {image.mode}; expected RGB")
    return paths


class PlayPublisher:
    def __init__(self, service_account: Path) -> None:
        try:
            from google.auth.transport.requests import AuthorizedSession
            from google.oauth2 import service_account as google_service_account
        except ImportError as error:
            raise RuntimeError(
                "Install tools/requirements-play-store.txt before using remote modes"
            ) from error

        credentials = google_service_account.Credentials.from_service_account_file(
            service_account,
            scopes=SCOPES,
        )
        self.session = AuthorizedSession(credentials)

    def request(self, method: str, url: str, **kwargs):
        response = self.session.request(method, url, timeout=120, **kwargs)
        if not response.ok:
            raise RuntimeError(f"Google Play API {method} {url} failed: {response.status_code} {response.text}")
        if not response.content:
            return {}
        return response.json()

    def create_edit(self) -> str:
        result = self.request(
            "POST",
            f"{API_ROOT}/applications/{PACKAGE_NAME}/edits",
            json={},
        )
        return result["id"]

    def get_listing(self, edit_id: str, locale: str) -> dict[str, str] | None:
        url = (
            f"{API_ROOT}/applications/{PACKAGE_NAME}/edits/{edit_id}/listings/"
            f"{quote(locale, safe='')}"
        )
        response = self.session.get(url, timeout=120)
        if response.status_code == 404:
            return None
        if not response.ok:
            raise RuntimeError(f"Google Play API GET {url} failed: {response.status_code} {response.text}")
        return response.json()

    def update_listing(self, edit_id: str, listing: Listing) -> None:
        self.request(
            "PUT",
            f"{API_ROOT}/applications/{PACKAGE_NAME}/edits/{edit_id}/listings/{quote(listing.locale, safe='')}",
            json=listing.as_api_payload(),
        )

    def replace_images(
        self,
        edit_id: str,
        locale: str,
        image_type: str,
        paths: list[Path],
    ) -> None:
        base = (
            f"/applications/{PACKAGE_NAME}/edits/{edit_id}/listings/"
            f"{quote(locale, safe='')}/{image_type}"
        )
        self.request("DELETE", f"{API_ROOT}{base}")
        for path in paths:
            self.request(
                "POST",
                f"{UPLOAD_ROOT}{base}?uploadType=media",
                data=path.read_bytes(),
                headers={"Content-Type": "image/png"},
            )

    def image_count(self, edit_id: str, locale: str, image_type: str) -> int:
        result = self.request(
            "GET",
            f"{API_ROOT}/applications/{PACKAGE_NAME}/edits/{edit_id}/listings/"
            f"{quote(locale, safe='')}/{image_type}",
        )
        return len(result.get("images", []))

    def commit(self, edit_id: str) -> dict:
        return self.request(
            "POST",
            f"{API_ROOT}/applications/{PACKAGE_NAME}/edits/{edit_id}:commit",
        )


def listing_diff(local: Listing, remote: dict[str, str] | None) -> str:
    remote_payload = remote or {}
    local_text = json.dumps(local.as_api_payload(), ensure_ascii=False, indent=2, sort_keys=True).splitlines()
    remote_text = json.dumps(remote_payload, ensure_ascii=False, indent=2, sort_keys=True).splitlines()
    return "\n".join(
        difflib.unified_diff(
            remote_text,
            local_text,
            fromfile=f"Play/{local.locale}",
            tofile=f"repo/{local.locale}",
            lineterm="",
        )
    )


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--locales",
        default=",".join(DEFAULT_LOCALES),
        help="Comma-separated Play locales",
    )
    parser.add_argument(
        "--service-account",
        type=Path,
        default=Path.home() / ".secrets" / "google-play-service-account.json",
    )
    parser.add_argument("--remote-diff", action="store_true")
    parser.add_argument("--commit", action="store_true")
    parser.add_argument("--no-images", action="store_true")
    parser.add_argument("--include-tablets", action="store_true")
    parser.set_defaults(project_root=project_root)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root: Path = args.project_root
    locales = tuple(locale.strip() for locale in args.locales.split(",") if locale.strip())
    unsupported = set(locales) - LOCALE_SOURCES.keys()
    if unsupported:
        raise ValueError(f"Unsupported locales: {', '.join(sorted(unsupported))}")

    listings = {
        locale: parse_listing(project_root / "store_listing" / LOCALE_SOURCES[locale], locale)
        for locale in locales
    }
    phone_assets: dict[str, list[Path]] = {}
    if not args.no_images:
        for locale in locales:
            phone_assets[locale] = validate_screenshots(
                screenshot_dir(project_root, locale, "phone"),
                (1080, 1920),
            )

    tablet_assets: dict[str, list[Path]] = {}
    if args.include_tablets:
        if "en-US" not in locales:
            raise ValueError("--include-tablets requires en-US in --locales")
        tablet_assets["7-inch"] = validate_screenshots(
            screenshot_dir(project_root, "en-US", "7-inch"),
            (1200, 1920),
        )
        tablet_assets["10-inch"] = validate_screenshots(
            screenshot_dir(project_root, "en-US", "10-inch"),
            (1600, 2560),
        )

    print(f"Validated {len(listings)} listings")
    for listing in listings.values():
        print(
            f"  {listing.locale}: title={len(listing.title)}, "
            f"short={len(listing.short_description)}, full={len(listing.full_description)}"
        )

    if not args.remote_diff and not args.commit:
        return
    if not args.service_account.exists():
        raise FileNotFoundError(args.service_account)

    publisher = PlayPublisher(args.service_account)
    edit_id = publisher.create_edit()
    print(f"Created Play edit {edit_id}")
    for locale, listing in listings.items():
        remote = publisher.get_listing(edit_id, locale)
        diff = listing_diff(listing, remote)
        print(diff or f"{locale}: no metadata changes")

    if not args.commit:
        print("Dry run complete; the uncommitted edit will expire automatically")
        return

    for locale, listing in listings.items():
        publisher.update_listing(edit_id, listing)
        if locale in phone_assets:
            publisher.replace_images(
                edit_id,
                locale,
                SCREENSHOT_TYPES["phone"],
                phone_assets[locale],
            )
    for device_class, paths in tablet_assets.items():
        publisher.replace_images(
            edit_id,
            "en-US",
            SCREENSHOT_TYPES[device_class],
            paths,
        )

    for locale, listing in listings.items():
        remote = publisher.get_listing(edit_id, locale)
        if remote is None or any(
            remote.get(field) != value
            for field, value in listing.as_api_payload().items()
        ):
            raise RuntimeError(f"Remote listing readback failed for {locale}")
        if locale in phone_assets:
            count = publisher.image_count(edit_id, locale, SCREENSHOT_TYPES["phone"])
            if count != 6:
                raise RuntimeError(f"Remote phone screenshot readback for {locale} returned {count}")
    for device_class in tablet_assets:
        count = publisher.image_count(edit_id, "en-US", SCREENSHOT_TYPES[device_class])
        if count != 6:
            raise RuntimeError(f"Remote {device_class} screenshot readback returned {count}")

    result = publisher.commit(edit_id)
    print(f"Committed Play edit {result.get('id', edit_id)}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
