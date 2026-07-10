from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps, ImageStat


ProgressCallback = Callable[[int, str], None]


@dataclass(frozen=True, slots=True)
class StackSummary:
    output_path: Path
    input_count: int
    accepted_count: int
    rejected_indices: list[int]
    shifts: list[tuple[int, int]]


def _load_rgb(path: Path) -> np.ndarray:
    try:
        with Image.open(path) as image:
            return np.asarray(ImageOps.exif_transpose(image).convert("RGB"), dtype=np.float32)
    except Exception as exc:
        raise ValueError(f"无法读取图像 {path.name}：{exc}") from exc


def _oriented_size(path: Path) -> tuple[int, int]:
    try:
        with Image.open(path) as image:
            width, height = image.size
            orientation = int(image.getexif().get(274, 1))
            return (height, width) if orientation in {5, 6, 7, 8} else (width, height)
    except Exception as exc:
        raise ValueError(f"无法读取图像 {path.name}：{exc}") from exc


def _load_preview(path: Path, max_dimension: int = 1200) -> np.ndarray:
    """读取用于质量判断与配准的小图，避免把 R7 全分辨率帧常驻内存。"""

    try:
        with Image.open(path) as image:
            preview = ImageOps.exif_transpose(image).convert("RGB")
            preview.thumbnail((max_dimension, max_dimension), Image.Resampling.BILINEAR)
            return np.asarray(preview, dtype=np.float32)
    except Exception as exc:
        raise ValueError(f"无法读取图像 {path.name}：{exc}") from exc


def _gray(array: np.ndarray) -> np.ndarray:
    return array[..., 0] * 0.2126 + array[..., 1] * 0.7152 + array[..., 2] * 0.0722


def _sharpness(array: np.ndarray) -> float:
    gray = _gray(array)
    # 梯度能量足以识别明显虚焦、云层遮挡和抖动帧，又不引入 OpenCV 依赖。
    dx = np.diff(gray, axis=1)
    dy = np.diff(gray, axis=0)
    return float((np.mean(dx * dx) + np.mean(dy * dy)) / 2)


def estimate_alignment_shift(reference: np.ndarray, moving: np.ndarray) -> tuple[int, int]:
    """用相位相关估计需施加到 moving 上的整数 (dy, dx) 位移。"""

    if reference.shape != moving.shape:
        raise ValueError("参与配准的图像尺寸必须一致")
    ref_gray = _gray(reference)
    moving_gray = _gray(moving)
    # 去均值和汉宁窗可压低城市渐变背景、图像边界对相关峰的干扰。
    window = np.outer(np.hanning(ref_gray.shape[0]), np.hanning(ref_gray.shape[1]))
    ref_fft = np.fft.fft2((ref_gray - np.mean(ref_gray)) * window)
    moving_fft = np.fft.fft2((moving_gray - np.mean(moving_gray)) * window)
    cross_power = ref_fft * np.conj(moving_fft)
    cross_power /= np.maximum(np.abs(cross_power), 1e-9)
    correlation = np.fft.ifft2(cross_power)
    peak_y, peak_x = np.unravel_index(np.argmax(np.abs(correlation)), correlation.shape)
    if peak_y > ref_gray.shape[0] // 2:
        peak_y -= ref_gray.shape[0]
    if peak_x > ref_gray.shape[1] // 2:
        peak_x -= ref_gray.shape[1]
    return int(peak_y), int(peak_x)


def _common_valid_crop(shape: tuple[int, int], shifts: list[tuple[int, int]]) -> tuple[slice, slice]:
    height, width = shape
    y0 = max(max(0, dy) for dy, _ in shifts)
    y1 = min(min(height, height + dy) for dy, _ in shifts)
    x0 = max(max(0, dx) for _, dx in shifts)
    x1 = min(min(width, width + dx) for _, dx in shifts)
    if y1 - y0 < height * 0.5 or x1 - x0 < width * 0.5:
        raise ValueError("帧间漂移过大，公共画面不足 50%，请检查赤道仪跟踪或输入文件")
    return slice(y0, y1), slice(x0, x1)


def _correct_light_pollution_image(image: Image.Image) -> Image.Image:
    radius = max(12.0, min(image.size) / 18.0)
    background = image.filter(ImageFilter.GaussianBlur(radius=radius))
    # 用背景平均亮度作为减法偏置，避免黑场被全部截断；这是确定性低频校正，
    # 不会像生成式模型那样凭空补星或改变星点位置。
    neutral_level = int(sum(ImageStat.Stat(background.resize((1, 1))).mean) / 3)
    corrected = ImageChops.subtract(image, background, scale=1.0, offset=neutral_level)
    return ImageOps.autocontrast(corrected, cutoff=(0.5, 0.2), preserve_tone=True)


def correct_light_pollution(array: np.ndarray) -> np.ndarray:
    """估计大尺度光污染背景并保留小尺度星点。

    这里不使用生成式模型，仅从原图减去低频背景。结果会与原片分别保存，便于
    比赛现场说明处理的可追溯性和天体位置真实性。
    """

    image = Image.fromarray(np.clip(array, 0, 255).astype(np.uint8))
    return np.asarray(_correct_light_pollution_image(image), dtype=np.float32)


def stack_images(
    paths: list[Path],
    output_path: Path,
    *,
    reject_bad_frames: bool = True,
    light_pollution: bool = True,
    progress: ProgressCallback | None = None,
) -> StackSummary:
    if len(paths) < 2:
        raise ValueError("至少需要两张 JPEG/PNG 才能堆栈")
    progress = progress or (lambda _value, _message: None)
    full_width, full_height = _oriented_size(paths[0])
    if any(_oriented_size(path) != (full_width, full_height) for path in paths[1:]):
        raise ValueError("堆栈图像尺寸不一致；请先使用同一相机和方向完成拍摄")

    # 配准只保留一张参考缩略图，其余逐张计算后立即释放。即使输入 200 帧，
    # 内存占用也不会随帧数线性增长。
    reference_preview = _load_preview(paths[0])
    preview_height, preview_width = reference_preview.shape[:2]
    scores = [_sharpness(reference_preview)]
    medians = [max(1.0, float(np.median(_gray(reference_preview))))]
    preview_shifts = [(0, 0)]
    for index, path in enumerate(paths[1:], start=1):
        preview = _load_preview(path)
        if preview.shape != reference_preview.shape:
            raise ValueError("生成配准缩略图后尺寸不一致")
        scores.append(_sharpness(preview))
        medians.append(max(1.0, float(np.median(_gray(preview)))))
        preview_shifts.append(estimate_alignment_shift(reference_preview, preview))
        progress(5 + math.floor(50 * (index + 1) / len(paths)), f"质量检查与星点配准 {index + 1}/{len(paths)}")

    accepted_indices = list(range(len(paths)))
    if reject_bad_frames and len(paths) >= 3:
        score_array = np.asarray(scores)
        median = float(np.median(score_array))
        # 阈值只剔除明显失焦/遮挡帧，避免星点较少的正常暗帧被过度清理。
        accepted_indices = [
            index for index, score in enumerate(score_array) if score >= max(1e-6, median * 0.35)
        ]
        if len(accepted_indices) < 2:
            accepted_indices = [int(index) for index in np.argsort(score_array)[-2:]]
    rejected = sorted(set(range(len(paths))) - set(accepted_indices))

    scale_y = full_height / preview_height
    scale_x = full_width / preview_width
    all_full_shifts = [
        (int(round(dy * scale_y)), int(round(dx * scale_x))) for dy, dx in preview_shifts
    ]
    shifts = [all_full_shifts[index] for index in accepted_indices]
    crop_y, crop_x = _common_valid_crop((full_height, full_width), shifts)
    y0, y1 = crop_y.start or 0, crop_y.stop or full_height
    x0, x1 = crop_x.start or 0, crop_x.stop or full_width
    reference_median = medians[accepted_indices[0]]

    accumulator: Image.Image | None = None
    for accepted_position, (source_index, (dy, dx)) in enumerate(zip(accepted_indices, shifts, strict=True)):
        try:
            with Image.open(paths[source_index]) as source:
                oriented = ImageOps.exif_transpose(source).convert("RGB")
                aligned = oriented.crop((x0 - dx, y0 - dy, x1 - dx, y1 - dy))
        except Exception as exc:
            raise ValueError(f"无法读取图像 {paths[source_index].name}：{exc}") from exc
        brightness_factor = max(0.25, min(4.0, reference_median / medians[source_index]))
        if abs(brightness_factor - 1.0) > 0.01:
            normalized = ImageEnhance.Brightness(aligned).enhance(brightness_factor)
            aligned.close()
            aligned = normalized
        if accumulator is None:
            accumulator = aligned
        else:
            previous = accumulator
            accumulator = Image.blend(previous, aligned, 1.0 / (accepted_position + 1))
            previous.close()
            aligned.close()
        progress(
            55 + math.floor(25 * (accepted_position + 1) / len(accepted_indices)),
            f"原分辨率融合 {accepted_position + 1}/{len(accepted_indices)}",
        )
    assert accumulator is not None
    progress(75, "完成多帧合成")
    if light_pollution:
        corrected = _correct_light_pollution_image(accumulator)
        accumulator.close()
        accumulator = corrected
        progress(90, "完成光污染背景校正")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.suffix.lower() in {".jpg", ".jpeg"}:
        accumulator.save(output_path, "JPEG", quality=95, subsampling=0)
    else:
        accumulator.save(output_path, "PNG", compress_level=3)
    accumulator.close()
    progress(100, "堆栈处理完成")
    return StackSummary(output_path, len(paths), len(accepted_indices), rejected, shifts)
