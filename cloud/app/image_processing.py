"""本地轻量增强和星点保护。

这里不生成天体，也不改变星点坐标。所有候选增强结果都会在输出前与原图按星点掩膜混合，
掩膜核心区域使用原始像素；边缘采用平滑权重，避免出现生硬光圈。
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageOps, UnidentifiedImageError


ALGORITHM_VERSION = "star-protect-local-v1"
MAX_IMAGE_PIXELS = 60_000_000
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS


@dataclass(frozen=True)
class ProcessingStats:
    algorithm_version: str
    threshold: float
    protected_pixel_ratio: float
    width: int
    height: int


def decode_image(content: bytes) -> tuple[Image.Image, str]:
    try:
        with Image.open(BytesIO(content)) as opened:
            image_format = (opened.format or "JPEG").upper()
            if image_format not in {"JPEG", "PNG", "WEBP"}:
                raise ValueError("仅支持 JPEG、PNG 或 WebP 图像")
            image = ImageOps.exif_transpose(opened).convert("RGB")
            image.load()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ValueError("上传内容不是可识别的 JPEG/PNG/WebP 图像") from exc
    return image, image_format


def load_image(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        image.load()
    return image


def _histogram_quantile(histogram: list[int], quantile: float) -> int:
    target = max(0, min(sum(histogram) - 1, int(sum(histogram) * quantile)))
    cumulative = 0
    for value, count in enumerate(histogram):
        cumulative += count
        if cumulative > target:
            return value
    return len(histogram) - 1


def detect_star_mask(image: Image.Image) -> tuple[Image.Image, float]:
    # 全分辨率只保留 8 位单通道图，避免 R7 原图被展开成多个数百 MB 的浮点数组。
    gray = ImageOps.grayscale(image)
    local_background = gray.filter(ImageFilter.GaussianBlur(2.2))
    high_pass = ImageChops.subtract(gray, local_background)

    high_pass_histogram = high_pass.histogram()
    median = _histogram_quantile(high_pass_histogram, 0.5)
    deviation_histogram = [0] * 256
    for value, count in enumerate(high_pass_histogram):
        deviation_histogram[abs(value - median)] += count
    mad = _histogram_quantile(deviation_histogram, 0.5)
    robust_threshold = median + max(7.0, 6.0 * 1.4826 * mad)
    percentile_threshold = _histogram_quantile(high_pass_histogram, 0.9915)
    threshold = min(255, max(robust_threshold, float(percentile_threshold)))
    brightness_floor = _histogram_quantile(gray.histogram(), 0.72)

    high_pass_binary = high_pass.point(
        [255 if value >= threshold else 0 for value in range(256)]
    )
    bright_binary = gray.point(
        [255 if value >= brightness_floor else 0 for value in range(256)]
    )
    core_image = ImageChops.multiply(high_pass_binary, bright_binary)
    # 先扩张再轻微模糊，让星点核心保持原像素，同时平滑过渡到增强后的背景。
    mask_image = core_image.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.8))
    return mask_image, threshold


def local_candidate(image: Image.Image, strength: float) -> Image.Image:
    strength = max(0.0, min(float(strength), 1.0))
    original = image.convert("RGB")
    denoised = original.filter(ImageFilter.MedianFilter(3))

    # 光污染背景只需要低频信息，先缩小后估计能显著降低树莓派的处理时间和峰值内存。
    background_source = original.copy()
    background_source.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
    radius = max(5.0, min(background_source.size) / 24.0)
    background = background_source.filter(ImageFilter.GaussianBlur(radius)).resize(
        original.size, Image.Resampling.BILINEAR
    )

    factor = 0.45 + 0.25 * strength
    corrected_bands: list[Image.Image] = []
    for denoised_band, background_band in zip(
        denoised.split(), background.split(), strict=True
    ):
        reference = _histogram_quantile(background_band.histogram(), 0.18)
        reference_image = Image.new("L", original.size, reference)
        scaled_background = Image.blend(reference_image, background_band, factor)
        corrected_bands.append(
            ImageChops.subtract(
                denoised_band,
                scaled_background,
                scale=1.0,
                offset=reference,
            )
        )

    corrected = Image.merge("RGB", corrected_bands)
    stretched = ImageOps.autocontrast(corrected, cutoff=(0.8, 0.35))
    return Image.blend(original, stretched, 0.72 * strength)


def protect_stars(
    original: Image.Image,
    candidate: Image.Image,
    mask: Image.Image,
) -> Image.Image:
    original_rgb = original.convert("RGB")
    candidate_rgb = candidate.convert("RGB")
    if original_rgb.size != candidate_rgb.size:
        raise ValueError("增强结果尺寸与原图不一致")
    if mask.size != original_rgb.size:
        raise ValueError("星点掩膜尺寸与原图不一致")

    return Image.composite(original_rgb, candidate_rgb, mask.convert("L"))


def save_mask(mask: Image.Image, path: Path) -> None:
    mask.convert("L").save(path, format="PNG")


def process_local(
    image: Image.Image,
    strength: float,
) -> tuple[Image.Image, Image.Image, ProcessingStats]:
    mask, threshold = detect_star_mask(image)
    candidate = local_candidate(image, strength)
    result = protect_stars(image, candidate, mask)
    stats = ProcessingStats(
        algorithm_version=ALGORITHM_VERSION,
        threshold=round(threshold, 4),
        protected_pixel_ratio=round(
            float(sum(mask.histogram()[128:]) / (mask.width * mask.height)), 8
        ),
        width=image.width,
        height=image.height,
    )
    return result, mask, stats
