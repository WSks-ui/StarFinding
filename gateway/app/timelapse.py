from __future__ import annotations

import shutil
from pathlib import Path
from typing import Callable

from PIL import Image, ImageOps

from .commands import CommandError, CommandRunner
from .config import Settings


class TimelapseEncoder:
    def __init__(self, settings: Settings, runner: CommandRunner | None = None) -> None:
        self.settings = settings
        self.runner = runner or CommandRunner()

    @property
    def available(self) -> bool:
        return self.runner.available(self.settings.ffmpeg_binary)

    def encode(
        self,
        image_paths: list[Path],
        output_path: Path,
        work_dir: Path,
        *,
        fps: int,
        width: int,
        height: int,
        progress: Callable[[int, str], None] | None = None,
    ) -> Path:
        if len(image_paths) < 2:
            raise ValueError("生成延时视频至少需要两帧")
        if width % 2 or height % 2:
            raise ValueError("H.264 yuv420p 输出的宽高必须为偶数")
        if not self.available:
            raise CommandError("未安装 FFmpeg，无法生成 H.264 延时视频")
        progress = progress or (lambda _value, _message: None)
        frames_dir = work_dir / "frames"
        if frames_dir.exists():
            shutil.rmtree(frames_dir)
        frames_dir.mkdir(parents=True)
        for index, source in enumerate(image_paths):
            try:
                with Image.open(source) as image:
                    frame = ImageOps.fit(
                        ImageOps.exif_transpose(image).convert("RGB"),
                        (width, height),
                        method=Image.Resampling.LANCZOS,
                    )
                    frame.save(frames_dir / f"frame_{index:06d}.jpg", "JPEG", quality=92)
            except Exception as exc:
                raise ValueError(f"无法准备视频帧 {source.name}：{exc}") from exc
            progress(5 + int(55 * (index + 1) / len(image_paths)), f"准备视频帧 {index + 1}/{len(image_paths)}")

        output_path.parent.mkdir(parents=True, exist_ok=True)
        args = [
            self.settings.ffmpeg_binary,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(fps),
            "-i",
            str(frames_dir / "frame_%06d.jpg"),
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(output_path),
        ]
        progress(65, "FFmpeg 正在编码 H.264 视频")
        self.runner.run(args, timeout=max(180.0, self.settings.command_timeout_seconds * 4))
        if not output_path.exists() or output_path.stat().st_size == 0:
            raise CommandError("FFmpeg 未生成有效视频文件")
        progress(100, "延时视频生成完成")
        return output_path
