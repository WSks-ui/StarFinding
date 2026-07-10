from __future__ import annotations

import re
import threading
import time
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .commands import CommandError, CommandRunner
from .config import Settings
from .models import CameraCapabilities, CameraStatus, CaptureRequest


class CameraAdapter(ABC):
    backend_name: str

    @abstractmethod
    def status(self) -> CameraStatus:
        raise NotImplementedError

    @abstractmethod
    def capabilities(self) -> CameraCapabilities:
        raise NotImplementedError

    @abstractmethod
    def capture(self, request: CaptureRequest, output_dir: Path, sequence: int) -> list[Path]:
        raise NotImplementedError

    @abstractmethod
    def liveview(self, output_path: Path) -> Path:
        raise NotImplementedError


class GPhotoCamera(CameraAdapter):
    """通过 gphoto2 CLI 串行控制 EOS R7。

    libgphoto2 对相机的访问不是为并发调用设计的。状态轮询、实时取景和拍摄共用
    一把锁，能避免比赛现场因 Pad 高频刷新状态而打断正在进行的长曝光。
    """

    backend_name = "gphoto2"

    def __init__(self, settings: Settings, runner: CommandRunner | None = None) -> None:
        self.settings = settings
        self.runner = runner or CommandRunner()
        self._lock = threading.RLock()

    def status(self) -> CameraStatus:
        if not self.runner.available(self.settings.gphoto2_binary):
            return CameraStatus(
                connected=False,
                backend="gphoto2",
                simulated=False,
                detail="未安装 gphoto2",
            )
        result = self.runner.run(
            [self.settings.gphoto2_binary, "--auto-detect"],
            timeout=self.settings.command_timeout_seconds,
            check=False,
        )
        lines = [line.strip() for line in result.stdout.splitlines()[2:] if line.strip()]
        if result.returncode != 0 or not lines:
            return CameraStatus(
                connected=False,
                backend="gphoto2",
                simulated=False,
                detail=(result.stderr.strip() or "未检测到相机")[-500:],
            )
        model = re.split(r"\s{2,}", lines[0], maxsplit=1)[0].strip()
        return CameraStatus(connected=True, backend="gphoto2", simulated=False, model=model, detail="USB 相机已连接")

    def _config_choices(self, names: list[str]) -> list[str]:
        for name in names:
            result = self.runner.run(
                [self.settings.gphoto2_binary, "--get-config", name],
                timeout=self.settings.command_timeout_seconds,
                check=False,
            )
            if result.returncode != 0:
                continue
            choices: list[str] = []
            for line in result.stdout.splitlines():
                match = re.match(r"Choice:\s+\d+\s+(.+)$", line.strip())
                if match:
                    choices.append(match.group(1).strip())
            if choices:
                return choices
        return []

    def capabilities(self) -> CameraCapabilities:
        with self._lock:
            iso = self._config_choices(["iso", "/main/imgsettings/iso"])
            aperture = self._config_choices(["aperture", "/main/capturesettings/aperture"])
            shutter = self._config_choices(["shutterspeed", "/main/capturesettings/shutterspeed"])
        bulb = any(value.lower() in {"bulb", "b"} for value in shutter)
        return CameraCapabilities(
            backend="gphoto2",
            liveview=True,
            raw_jpeg=True,
            bulb=bulb,
            max_exposure_seconds=300 if bulb else 30,
            iso_values=iso,
            aperture_values=aperture,
            shutter_values=shutter,
        )

    def capture(self, request: CaptureRequest, output_dir: Path, sequence: int) -> list[Path]:
        if request.exposure_seconds > 30:
            # EOS 的 Bulb 菜单与固件版本有关。首版先拒绝不可靠的超 30 秒调用，
            # Pad 会根据 capabilities 自动隐藏该范围，城市拍摄则使用短曝光堆栈。
            if not self.capabilities().bulb:
                raise CommandError("当前 R7/gphoto2 组合未报告 Bulb 能力，单帧曝光不能超过 30 秒")
            raise CommandError("Bulb 控制尚未通过本机 R7 验证，请暂用 30 秒内子曝光")

        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
        prefix = output_dir / f"{request.label}_{timestamp}_{sequence:04d}"
        filename_pattern = f"{prefix}.%C"
        args = [
            self.settings.gphoto2_binary,
            "--set-config",
            f"iso={request.iso}",
            "--set-config",
            f"aperture={request.aperture}",
            "--set-config",
            f"shutterspeed={request.exposure_seconds:g}",
            "--capture-image-and-download",
            "--keep",
            "--force-overwrite",
            "--filename",
            filename_pattern,
        ]
        with self._lock:
            self.runner.run(args, timeout=max(self.settings.capture_timeout_seconds, request.exposure_seconds + 45))
        files = sorted(path for path in output_dir.glob(f"{prefix.name}.*") if path.is_file())
        if not files:
            raise CommandError("gphoto2 报告拍摄完成，但没有找到下载文件")
        return files

    def liveview(self, output_path: Path) -> Path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with self._lock:
            self.runner.run(
                [
                    self.settings.gphoto2_binary,
                    "--capture-preview",
                    "--force-overwrite",
                    "--filename",
                    str(output_path),
                ],
                timeout=self.settings.command_timeout_seconds,
            )
        if not output_path.exists():
            raise CommandError("实时取景命令执行后未生成预览图")
        return output_path


class MockCamera(CameraAdapter):
    """无 R7 时使用的确定性星空模拟器，可完整联调 Pad 和任务流水线。"""

    backend_name = "mock"

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._counter = 0

    def status(self) -> CameraStatus:
        return CameraStatus(
            connected=True,
            backend="mock",
            simulated=True,
            model="StarFinding Simulated EOS R7",
            battery="100%",
            detail="模拟后端：未触发真实快门",
        )

    def capabilities(self) -> CameraCapabilities:
        return CameraCapabilities(
            backend="mock",
            liveview=True,
            raw_jpeg=True,
            bulb=True,
            max_exposure_seconds=300,
            iso_values=["100", "400", "800", "1600", "3200"],
            aperture_values=["2.8", "3.5", "4", "5.6", "8"],
            shutter_values=["1", "2", "5", "10", "15", "20", "30", "Bulb"],
        )

    def _render_sky(self, sequence: int, *, preview: bool = False) -> Image.Image:
        width, height = (960, 540) if preview else (1280, 720)
        rng = np.random.default_rng(self.settings.mock_seed)
        # 固定星点 + 随序号微量漂移，让堆栈算法在无硬件环境下也能验证配准。
        background = rng.normal(17 if preview else 22, 3.0, (height, width, 3))
        background[..., 0] += np.linspace(7, 28, height, dtype=np.float32)[:, None]
        background[..., 1] += np.linspace(5, 18, height, dtype=np.float32)[:, None]
        background[..., 2] += np.linspace(0, 7, height, dtype=np.float32)[:, None]
        image = Image.fromarray(np.clip(background, 0, 255).astype(np.uint8))
        draw = ImageDraw.Draw(image)
        drift_x = sequence % 5
        drift_y = (sequence // 2) % 4
        star_rng = np.random.default_rng(self.settings.mock_seed + 1)
        for _ in range(190):
            x = int(star_rng.integers(12, width - 12)) + drift_x
            y = int(star_rng.integers(12, height - 12)) + drift_y
            radius = int(star_rng.choice([1, 1, 1, 2, 2, 3]))
            color_temperature = int(star_rng.integers(-20, 21))
            color = (255, max(190, 245 - abs(color_temperature)), max(185, 235 + color_temperature))
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        return image.filter(ImageFilter.GaussianBlur(radius=0.35))

    def capture(self, request: CaptureRequest, output_dir: Path, sequence: int) -> list[Path]:
        output_dir.mkdir(parents=True, exist_ok=True)
        with self._lock:
            self._counter += 1
            own_counter = self._counter
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
        base = output_dir / f"{request.label}_{timestamp}_{sequence:04d}"
        jpeg_path = base.with_suffix(".jpg")
        self._render_sky(own_counter).save(jpeg_path, "JPEG", quality=94)
        paths = [jpeg_path]
        if request.raw_jpeg:
            # 这是显式标记的模拟占位文件，绝不伪装成可解码 CR3；接口联调可以借此
            # 验证 RAW/JPEG 双文件的保存、索引与下载行为。
            raw_path = base.with_suffix(".mock.cr3")
            raw_path.write_bytes(b"STARFINDING MOCK CR3\n")
            paths.append(raw_path)
        return paths

    def liveview(self, output_path: Path) -> Path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with self._lock:
            self._counter += 1
            own_counter = self._counter
        self._render_sky(own_counter, preview=True).save(output_path, "JPEG", quality=85)
        return output_path


def build_camera(settings: Settings, runner: CommandRunner | None = None) -> CameraAdapter:
    if settings.camera_backend not in {"auto", "gphoto2", "mock"}:
        raise ValueError("STARFINDING_CAMERA_BACKEND 仅支持 auto、gphoto2 或 mock")
    if settings.camera_backend == "mock":
        return MockCamera(settings)
    real = GPhotoCamera(settings, runner)
    if settings.camera_backend == "gphoto2":
        return real
    try:
        if real.status().connected:
            return real
    except Exception:
        if not settings.allow_mock_fallback:
            raise
    if not settings.allow_mock_fallback:
        return real
    return MockCamera(settings)
