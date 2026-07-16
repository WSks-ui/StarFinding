from __future__ import annotations

from pathlib import Path
from typing import Sequence

from app.camera import GPhotoCamera
from app.commands import CommandResult
from app.config import Settings
from app.models import CaptureRequest


class FakeGPhotoRunner:
    def __init__(self, values: dict[str, str | None], choices: dict[str, list[str]]) -> None:
        self.values = values
        self.choices = choices
        self.calls: list[tuple[str, ...]] = []

    @staticmethod
    def available(_binary: str) -> bool:
        return True

    def run(
        self,
        args: Sequence[str],
        *,
        timeout: float,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
        check: bool = True,
    ) -> CommandResult:
        del timeout, cwd, env, check
        call = tuple(str(item) for item in args)
        self.calls.append(call)
        if "--auto-detect" in call:
            stdout = "Model                          Port\n----------------------------------------------------------\nCanon EOS R7                   usb:001,002\n"
            return CommandResult(call, 0, stdout, "")
        if "--get-config" in call:
            name = call[-1]
            key = name.split("/")[-1]
            if key not in self.values and key not in self.choices:
                return CommandResult(call, 1, "", "配置不存在")
            lines = [f"Label: {key}"]
            current = self.values.get(key)
            if current is not None:
                lines.append(f"Current: {current}")
            for index, choice in enumerate(self.choices.get(key, [])):
                lines.append(f"Choice: {index} {choice}")
            return CommandResult(call, 0, "\n".join(lines), "")
        if "--capture-image-and-download" in call:
            pattern = Path(call[call.index("--filename") + 1])
            output = Path(str(pattern).replace("%C", "JPG"))
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(b"jpeg")
            return CommandResult(call, 0, "New file is in location", "")
        return CommandResult(call, 0, "", "")


def valid_values() -> tuple[dict[str, str | None], dict[str, list[str]]]:
    values: dict[str, str | None] = {
        "expprogram": "Manual",
        "imageformat": "RAW + Large Fine JPEG",
        "iso": "800",
        "aperture": "4",
        "shutterspeed": "10",
        "focusmode": "Manual",
    }
    choices: dict[str, list[str]] = {
        "expprogram": ["Manual", "Av", "Tv"],
        "imageformat": ["RAW + Large Fine JPEG", "Large Fine JPEG"],
        "iso": ["100", "400", "800", "1600"],
        "aperture": ["2.8", "4", "5.6"],
        "shutterspeed": ["1", "5", "10", "15", "30"],
        "focusmode": ["Manual", "Auto"],
    }
    return values, choices


def test_r7_preflight_accepts_matching_manual_settings(tmp_path: Path) -> None:
    values, choices = valid_values()
    runner = FakeGPhotoRunner(values, choices)
    camera = GPhotoCamera(Settings(data_dir=tmp_path), runner)

    result = camera.preflight("800", "4", 10)

    assert result.ready is True
    assert result.camera_model == "Canon EOS R7"
    assert result.blockers == []
    assert all(check.passed for check in result.checks)


def test_r7_preflight_reports_real_blockers_and_focus_warning(tmp_path: Path) -> None:
    values, choices = valid_values()
    values["expprogram"] = "Aperture Priority"
    values["imageformat"] = "Large Fine JPEG"
    values["iso"] = "400"
    values["focusmode"] = None
    choices["focusmode"] = []
    runner = FakeGPhotoRunner(values, choices)
    camera = GPhotoCamera(Settings(data_dir=tmp_path), runner)

    result = camera.preflight("800", "4", 10)

    assert result.ready is False
    assert {"曝光模式", "图像格式", "ISO"}.issubset(set(result.blockers))
    focus = next(check for check in result.checks if check.code == "focus")
    assert focus.passed is False
    assert focus.blocking is False
    assert result.warnings


def test_capture_does_not_modify_camera_configuration(tmp_path: Path) -> None:
    values, choices = valid_values()
    runner = FakeGPhotoRunner(values, choices)
    settings = Settings(data_dir=tmp_path, capture_timeout_seconds=60)
    camera = GPhotoCamera(settings, runner)
    output_dir = tmp_path / "captures"
    request = CaptureRequest(
        iso="800",
        aperture="4",
        exposure_seconds=10,
        count=1,
        raw_jpeg=True,
        label="preflighted",
    )

    files = camera.capture(request, output_dir, 1)

    capture_call = next(call for call in runner.calls if "--capture-image-and-download" in call)
    assert "--set-config" not in capture_call
    assert "--keep" in capture_call
    assert files and files[0].suffix == ".JPG"
