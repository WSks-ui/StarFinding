#!/usr/bin/env python3
"""Build StarFinding's high-resolution, horizontally seamless ESO Milky Way texture.

The script intentionally is a build-time tool, not a runtime dependency. It verifies the official
6000x3000 ESO/S. Brunier all-sky image, preserves the original pixels, and only blends a narrow
periodic strip at the left/right texture seam. Photography mode already hides the duplicate HYG
point layer, so source stars and nebula detail must remain intact.
"""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

from PIL import Image

SOURCE_SHA256 = (
    "60400C92C54B7C1BD12299C69E83B16E5B6256E7DABACC478C021758ECD28179"
)
WIDTH = 6000
HEIGHT = 3000
SEAM_BLEND_WIDTH = 64


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
        default=Path(
            "entry/src/main/resources/rawfile/sky_survey_eso_visible_6000x3000.png"
        ),
    )
    args = parser.parse_args()
    if sha256(args.source) != SOURCE_SHA256:
        raise SystemExit("ESO source SHA-256 mismatch")

    source = Image.open(args.source).convert("RGB")
    if source.size != (6000, 3000):
        raise SystemExit(f"unexpected source dimensions: {source.size}")

    # 等距柱状全天图的左右边缘对应同一银河经度。官方 JPEG 两侧因拼接与压缩并非逐像素
    # 相等；若直接贴到闭合球面，即使几何顶点完全重合，仍可能留下细竖缝。这里只在约
    # 3.8° 宽的边缘带内使用余弦权重趋向成对平均值，中心 99% 以上影像保持原样。
    pixels = source.load()
    for distance in range(SEAM_BLEND_WIDTH):
        left_x = distance
        right_x = WIDTH - 1 - distance
        ratio = distance / max(1, SEAM_BLEND_WIDTH - 1)
        weight = 0.5 * (1.0 + math.cos(math.pi * ratio))
        for y in range(HEIGHT):
            left = pixels[left_x, y]
            right = pixels[right_x, y]
            average = tuple(round((left[channel] + right[channel]) * 0.5) for channel in range(3))
            pixels[left_x, y] = tuple(
                round(left[channel] * (1.0 - weight) + average[channel] * weight)
                for channel in range(3)
            )
            pixels[right_x, y] = tuple(
                round(right[channel] * (1.0 - weight) + average[channel] * weight)
                for channel in range(3)
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    # PNG 避免 JPEG 分块压缩再次让首末列产生差异；应用只在首次进入摄影模式时解码一次。
    source.save(args.output, format="PNG", optimize=True, compress_level=6)
    rebuilt = Image.open(args.output).convert("RGB")
    for y in range(HEIGHT):
        if rebuilt.getpixel((0, y)) != rebuilt.getpixel((WIDTH - 1, y)):
            raise SystemExit(f"output texture seam mismatch at row {y}")
    print(f"{args.output} {args.output.stat().st_size} bytes")
    print(f"derived SHA-256 {sha256(args.output)}")


if __name__ == "__main__":
    main()
