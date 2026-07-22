#!/usr/bin/env python3
"""Build StarFinding's diffuse ESO visible-light Milky Way texture.

The script intentionally is a build-time tool, not a runtime dependency. It reads the official
6000x3000 ESO/S. Brunier all-sky image, suppresses point sources and historical moving-object
residuals with a median + Gaussian filter, and writes a fixed Galactic equirectangular RGB raster.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

SOURCE_SHA256 = (
    "60400C92C54B7C1BD12299C69E83B16E5B6256E7DABACC478C021758ECD28179"
)
WIDTH = 1536
HEIGHT = 768


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("entry/src/main/resources/rawfile/sky_survey_eso_visible_diffuse.rgb"),
    )
    args = parser.parse_args()
    if sha256(args.source) != SOURCE_SHA256:
        raise SystemExit("ESO source SHA-256 mismatch")

    source = Image.open(args.source).convert("RGB")
    if source.size != (6000, 3000):
        raise SystemExit(f"unexpected source dimensions: {source.size}")

    resized = source.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    # Point sources include catalog stars and the original panorama's historical solar-system traces.
    diffuse = resized.filter(ImageFilter.MedianFilter(size=9))
    diffuse = diffuse.filter(ImageFilter.GaussianBlur(radius=0.9))
    diffuse = ImageEnhance.Contrast(diffuse).enhance(1.14)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(diffuse.tobytes())
    print(f"{args.output} {args.output.stat().st_size} bytes")
    print(f"derived SHA-256 {sha256(args.output)}")


if __name__ == "__main__":
    main()
