from __future__ import annotations

import re
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .commands import CommandError, CommandRunner
from .config import Settings
from .models import CameraCapabilities, CameraPreflightCheck, CameraPreflightResult, CameraStatus, CaptureRequest


@dataclass(frozen=True, slots=True)
class CameraConfigReading:
    current: str | None
    choices: list[str]


class CameraAdapter(ABC):
    backend_name: str

    @abstractmethod
    def status(self) -> CameraStatus:
        raise NotImplementedError

    @abstractmethod
    def capabilities(self) -> CameraCapabilities:
        raise NotImplementedError

    @abstractmethod
    def preflight(self, iso: str, aperture: str, exposure_seconds: float) -> CameraPreflightResult:
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

    def _read_config(self, names: list[str]) -> CameraConfigReading:
        for name in names:
            result = self.runner.run(
                [self.settings.gphoto2_binary, "--get-config", name],
                timeout=self.settings.command_timeout_seconds,
                check=False,
            )
            if result.returncode != 0:
                continue
            current: str | None = None
            choices: list[str] = []
            for line in result.stdout.splitlines():
                stripped = line.strip()
                current_match = re.match(r"Current:\s*(.*)$", stripped)
                if current_match:
                    current = current_match.group(1).strip()
                match = re.match(r"Choice:\s+\d+\s+(.+)$", stripped)
                if match:
                    choices.append(match.group(1).strip())
            if current is not None or choices:
                return CameraConfigReading(current=current, choices=choices)
        return CameraConfigReading(current=None, choices=[])

    def _config_choices(self, names: list[str]) -> list[str]:
        return self._read_config(names).choices

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

    @staticmethod
    def _normalized(value: str | None) -> str:
        return "" if value is None else re.sub(r"\s+", " ", value.strip().lower())

    @staticmethod
    def _numeric_setting_matches(actual: str | None, expected: str) -> bool:
        if actual is None:
            return False
        normalized_actual = actual.lower().replace("f/", "").strip()
        normalized_expected = expected.lower().replace("f/", "").strip()
        try:
            return abs(float(normalized_actual) - float(normalized_expected)) < 0.0001
        except ValueError:
            return normalized_actual == normalized_expected

    @staticmethod
    def _shutter_seconds(value: str | None) -> float | None:
        if value is None:
            return None
        normalized = value.strip().lower().replace("seconds", "").replace("second", "").replace("sec", "")
        normalized = normalized.replace('"', "").replace("s", "").strip()
        if normalized in {"bulb", "b"}:
            return None
        try:
            if "/" in normalized:
                numerator, denominator = normalized.split("/", maxsplit=1)
                return float(numerator) / float(denominator)
            return float(normalized)
        except (ValueError, ZeroDivisionError):
            return None

    @classmethod
    def _shutter_matches(cls, value: str | None, expected_seconds: float) -> bool:
        seconds = cls._shutter_seconds(value)
        if seconds is None:
            return False
        return abs(seconds - expected_seconds) <= max(0.00001, expected_seconds * 0.001)

    @staticmethod
    def _expected_shutter(exposure_seconds: float) -> str:
        if exposure_seconds >= 1:
            return f"{exposure_seconds:g} s"
        denominator = round(1 / exposure_seconds)
        return f"1/{denominator} s"

    @staticmethod
    def _check(code: str, label: str, actual: str | None, expected: str, passed: bool,
               blocking: bool, adjustment: str) -> CameraPreflightCheck:
        return CameraPreflightCheck(
            code=code,
            label=label,
            actual=actual if actual else "无法读取",
            expected=expected,
            passed=passed,
            blocking=blocking,
            adjustment=adjustment,
        )

    def preflight(self, iso: str, aperture: str, exposure_seconds: float) -> CameraPreflightResult:
        with self._lock:
            status = self.status()
            if not status.connected:
                check = self._check(
                    "camera_connected", "相机连接", status.detail, "EOS R7 USB 已连接", False, True,
                    "检查 USB-C 数据线、关闭相机 Wi-Fi/蓝牙，并重新打开相机电源",
                )
                return CameraPreflightResult(
                    ready=False,
                    connected=False,
                    backend="gphoto2",
                    simulated=False,
                    camera_model=status.model,
                    checks=[check],
                    blockers=[check.label],
                )

            exposure_mode = self._read_config(["expprogram", "/main/capturesettings/expprogram"])
            image_format = self._read_config(["imageformat", "/main/imgsettings/imageformat"])
            iso_reading = self._read_config(["iso", "/main/imgsettings/iso"])
            aperture_reading = self._read_config(["aperture", "/main/capturesettings/aperture"])
            shutter_reading = self._read_config(["shutterspeed", "/main/capturesettings/shutterspeed"])
            focus_reading = self._read_config(["focusmode", "/main/capturesettings/focusmode"])

        model_ok = status.model is not None and "eos r7" in status.model.lower()
        mode_value = self._normalized(exposure_mode.current)
        manual_mode = mode_value in {"m", "manual"} or "manual" in mode_value
        format_value = self._normalized(image_format.current)
        raw_jpeg = "raw" in format_value and (
            "jpeg" in format_value or "jpg" in format_value or "large fine" in format_value
        )
        iso_supported = any(self._numeric_setting_matches(choice, iso) for choice in iso_reading.choices)
        iso_current = self._numeric_setting_matches(iso_reading.current, iso)
        aperture_supported = any(
            self._numeric_setting_matches(choice, aperture) for choice in aperture_reading.choices
        )
        aperture_current = self._numeric_setting_matches(aperture_reading.current, aperture)
        shutter_supported = any(
            self._shutter_matches(choice, exposure_seconds) for choice in shutter_reading.choices
        )
        shutter_current = self._shutter_matches(shutter_reading.current, exposure_seconds)
        focus_value = self._normalized(focus_reading.current)
        focus_readable = focus_reading.current is not None
        manual_focus = focus_readable and (
            focus_value in {"mf", "manual"} or "manual" in focus_value
        )

        checks = [
            self._check("camera_connected", "相机连接", status.detail, "EOS R7 USB 已连接", True, True,
                        "检查 USB-C 数据线并重新打开相机电源"),
            self._check("camera_model", "相机型号", status.model, "Canon EOS R7", model_ok, True,
                        "连接 Canon EOS R7；当前链路未对其他机型完成验收"),
            self._check("exposure_mode", "曝光模式", exposure_mode.current, "M 手动曝光", manual_mode, True,
                        "将 R7 模式拨盘切换到 M"),
            self._check("image_format", "图像格式", image_format.current, "RAW + JPEG", raw_jpeg, True,
                        "在 R7 图像画质菜单中同时启用 CR3 RAW 与 JPEG"),
            self._check("iso", "ISO", iso_reading.current, iso, iso_supported and iso_current, True,
                        f"在 R7 快速控制中将 ISO 调整为 {iso}"),
            self._check("aperture", "光圈", aperture_reading.current, f"f/{aperture}",
                        aperture_supported and aperture_current, True,
                        f"在 M 模式下将光圈调整为 f/{aperture}"),
            self._check("shutter", "快门", shutter_reading.current, self._expected_shutter(exposure_seconds),
                        shutter_supported and shutter_current, True,
                        f"在 M 模式下将快门调整为 {self._expected_shutter(exposure_seconds)}"),
            self._check("focus", "对焦模式", focus_reading.current, "MF 手动对焦", manual_focus,
                        focus_readable, "将镜头 AF/MF 开关切换到 MF，并在星点上完成放大对焦"),
        ]
        blockers = [check.label for check in checks if check.blocking and not check.passed]
        warnings = [
            "gphoto2 无法读取镜头对焦模式，请人工确认镜头已切到 MF"
        ] if not focus_readable else []
        return CameraPreflightResult(
            ready=not blockers,
            connected=True,
            backend="gphoto2",
            simulated=False,
            camera_model=status.model,
            checks=checks,
            blockers=blockers,
            warnings=warnings,
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

    def preflight(self, iso: str, aperture: str, exposure_seconds: float) -> CameraPreflightResult:
        check = CameraPreflightCheck(
            code="real_camera",
            label="真实相机",
            actual="模拟相机后端",
            expected="Canon EOS R7 / gphoto2",
            passed=False,
            blocking=True,
            adjustment="将 STARFINDING_CAMERA_BACKEND 设为 gphoto2，并通过 USB 连接 EOS R7",
        )
        return CameraPreflightResult(
            ready=False,
            connected=True,
            backend="mock",
            simulated=True,
            camera_model="StarFinding Simulated EOS R7",
            checks=[check],
            blockers=[check.label],
            warnings=[f"模拟后端未触发快门：ISO {iso}、f/{aperture}、{exposure_seconds:g} s"],
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
