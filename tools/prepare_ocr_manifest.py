"""Prepare the pinned on-device OCR model manifest. Inputs are read-only; weights stay in build.
Run with Python 3.11+; no inference libraries or credentials are required.

Example:
  python tools/prepare_ocr_manifest.py --manga-ocr-dir build/ocr-research/manga_ocr_onnx \
      --detector build/ocr/models/comictextdetector.onnx
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# kha-white/manga-ocr-base weights (the Mekuru OCR server's recognizer) and the
# onnx-community export of them; the tokenizer vocabulary comes from the source repo.
MANGA_OCR_REV = "aa6573bd10b0d446cbf622e29c3e084914df9741"
ONNX_REV = "f9023406bb2f6b17df67bc4a327c56ecd20611f0"
CTD = "293ae8060b08f2ed323693019f9bd0c173af4eab"
VERSION = "manga-ocr-base-onnx-v1"


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manga-ocr-dir", type=Path, required=True,
                        help="directory holding encoder_model_fp16.onnx, decoder_model_int8.onnx, vocab.txt")
    parser.add_argument("--detector", type=Path, required=True)
    args = parser.parse_args()
    files = []
    sources = [
        ("encoder_model_fp16.onnx",
         f"https://huggingface.co/onnx-community/manga-ocr-base-ONNX/resolve/{ONNX_REV}/onnx/encoder_model_fp16.onnx"),
        ("decoder_model_int8.onnx",
         f"https://huggingface.co/onnx-community/manga-ocr-base-ONNX/resolve/{ONNX_REV}/onnx/decoder_model_int8.onnx"),
        ("vocab.txt",
         f"https://huggingface.co/kha-white/manga-ocr-base/resolve/{MANGA_OCR_REV}/vocab.txt"),
    ]
    for name, url in sources:
        path = args.manga_ocr_dir / name
        files.append(dict(name=name, bytes=path.stat().st_size, sha256=sha256(path), url=url,
                          component="manga-ocr", license="Apache-2.0"))
    path = args.detector
    files.append(dict(name="comictextdetector.onnx", bytes=path.stat().st_size, sha256=sha256(path),
        url="https://github.com/zyddnys/manga-image-translator/releases/download/"
            "beta-0.2.1/comictextdetector.pt.onnx", component="comic-text-detector",
        license="GPL-3.0", licenseProvenance="Upstream detector project license; "
        "no separate weight license is included in the release asset. "
        "Redistribution provenance must be verified before release."))
    assets = ROOT / "packages/local_manga_ocr/android/src/main/assets/local_manga_ocr"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "manifest.json").write_text(json.dumps(dict(version=VERSION, files=files,
        totalBytes=sum(f["bytes"] for f in files), mangaOcrRevision=MANGA_OCR_REV,
        mangaOcrOnnxRevision=ONNX_REV, detectorRevision=CTD,
        runtime="onnxruntime-android:1.24.3",
        detectorRuntime="OpenCV 4.12.0 DNN CPU"), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
