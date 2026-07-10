from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageDraw

from app.commands import CommandError, CommandResult, CommandRunner
from app.config import Settings
from app.image_processing import estimate_alignment_shift, stack_images
from app.timelapse import TimelapseEncoder


def _star_frame(width: int = 240, height: int = 160) -> np.ndarray:
    image = Image.new("RGB", (width, height), (12, 14, 22))
    draw = ImageDraw.Draw(image)
    rng = np.random.default_rng(42)
    for _ in range(50):
        x, y = int(rng.integers(10, width - 10)), int(rng.integers(10, height - 10))
        draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(245, 245, 235))
    return np.asarray(image, dtype=np.float32)


def test_phase_alignment_and_stack(tmp_path: Path) -> None:
    reference = _star_frame()
    moving = np.roll(reference, shift=(4, -7), axis=(0, 1))
    assert estimate_alignment_shift(reference, moving) == (-4, 7)

    paths = []
    for index, array in enumerate((reference, moving, np.roll(reference, shift=(-2, 3), axis=(0, 1)))):
        path = tmp_path / f"frame-{index}.png"
        Image.fromarray(array.astype(np.uint8)).save(path)
        paths.append(path)
    output = tmp_path / "stack.jpg"
    summary = stack_images(paths, output, reject_bad_frames=False, light_pollution=True)
    assert output.is_file()
    assert summary.accepted_count == 3
    with Image.open(output) as result:
        assert result.width >= 200
        assert result.height >= 130


def test_command_runner_uses_literal_arguments_and_timeout() -> None:
    runner = CommandRunner()
    literal = "$(echo injected); & |"
    result = runner.run([sys.executable, "-c", "import sys; print(sys.argv[1])", literal], timeout=2)
    assert result.stdout.strip() == literal
    with pytest.raises(CommandError, match="超时"):
        runner.run([sys.executable, "-c", "import time; time.sleep(1)"], timeout=0.05)


class FakeFfmpegRunner:
    def available(self, _binary: str) -> bool:
        return True

    def run(self, args: list[str], **_kwargs: object) -> CommandResult:
        Path(args[-1]).write_bytes(b"mock mp4 produced by fake test runner")
        return CommandResult(tuple(args), 0, "", "")


def test_timelapse_prepares_frames_and_invokes_ffmpeg_without_shell(tmp_path: Path) -> None:
    sources = []
    for index, color in enumerate(((20, 30, 40), (30, 40, 50))):
        path = tmp_path / f"source {index}.jpg"
        Image.new("RGB", (160, 90), color).save(path)
        sources.append(path)
    settings = Settings(data_dir=tmp_path, ffmpeg_binary="ffmpeg")
    encoder = TimelapseEncoder(settings, FakeFfmpegRunner())
    output = tmp_path / "video.mp4"
    result = encoder.encode(sources, output, tmp_path / "work", fps=24, width=320, height=240)
    assert result == output
    assert output.stat().st_size > 0
    assert len(list((tmp_path / "work" / "frames").glob("frame_*.jpg"))) == 2
