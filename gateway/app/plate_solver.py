from __future__ import annotations

import re
from abc import ABC, abstractmethod
from pathlib import Path

from .commands import CommandError, CommandRunner
from .config import Settings
from .models import PlateSolveRequest, PlateSolveResult


class PlateSolver(ABC):
    backend_name: str

    @abstractmethod
    def solve(self, image_path: Path, request: PlateSolveRequest, work_dir: Path) -> PlateSolveResult:
        raise NotImplementedError


class AstrometryNetSolver(PlateSolver):
    backend_name = "astrometry.net"

    def __init__(self, settings: Settings, runner: CommandRunner | None = None) -> None:
        self.settings = settings
        self.runner = runner or CommandRunner()

    @property
    def available(self) -> bool:
        return self.runner.available(self.settings.solve_field_binary)

    def solve(self, image_path: Path, request: PlateSolveRequest, work_dir: Path) -> PlateSolveResult:
        work_dir.mkdir(parents=True, exist_ok=True)
        args = [
            self.settings.solve_field_binary,
            str(image_path),
            "--dir",
            str(work_dir),
            "--overwrite",
            "--no-plots",
            "--no-remove-lines",
        ]
        if request.hint_ra_deg is not None and request.hint_dec_deg is not None:
            args.extend(
                [
                    "--ra",
                    f"{request.hint_ra_deg:.8f}",
                    "--dec",
                    f"{request.hint_dec_deg:.8f}",
                    "--radius",
                    f"{request.search_radius_deg:.4f}",
                ]
            )
        if request.pixel_scale_low is not None and request.pixel_scale_high is not None:
            args.extend(
                [
                    "--scale-units",
                    "arcsecperpix",
                    "--scale-low",
                    f"{request.pixel_scale_low:.6f}",
                    "--scale-high",
                    f"{request.pixel_scale_high:.6f}",
                ]
            )
        result = self.runner.run(args, timeout=max(180.0, self.settings.capture_timeout_seconds), check=False)
        combined = f"{result.stdout}\n{result.stderr}"
        if result.returncode != 0 or "solved" not in combined.lower():
            return PlateSolveResult(
                solved=False,
                backend="astrometry.net",
                simulated=False,
                detail=(combined.strip() or "astrometry.net 未解算出结果")[-1200:],
            )

        center = re.search(
            r"Field center:\s*\(RA,Dec\)\s*=\s*\(([+-]?[\d.]+),\s*([+-]?[\d.]+)\)\s*deg",
            combined,
            re.IGNORECASE,
        )
        size = re.search(
            r"Field size:\s*([\d.]+)\s*x\s*([\d.]+)\s*degrees?",
            combined,
            re.IGNORECASE,
        )
        rotation = re.search(r"Field rotation angle:.*?([+-]?[\d.]+)\s*degrees", combined, re.IGNORECASE)
        scale = re.search(r"Field pixel scale:\s*([\d.]+)\s*arcsec", combined, re.IGNORECASE)
        if not center:
            raise CommandError("astrometry.net 已解算，但无法解析中心坐标；请保存日志检查工具版本")
        return PlateSolveResult(
            solved=True,
            backend="astrometry.net",
            simulated=False,
            ra_deg=float(center.group(1)),
            dec_deg=float(center.group(2)),
            rotation_deg=float(rotation.group(1)) if rotation else None,
            pixel_scale_arcsec=float(scale.group(1)) if scale else None,
            field_width_deg=float(size.group(1)) if size else None,
            field_height_deg=float(size.group(2)) if size else None,
            detail="astrometry.net 本地板解析成功",
        )


class MockPlateSolver(PlateSolver):
    backend_name = "mock"

    def solve(self, image_path: Path, request: PlateSolveRequest, work_dir: Path) -> PlateSolveResult:
        if not image_path.exists():
            raise FileNotFoundError(image_path)
        return PlateSolveResult(
            solved=True,
            backend="mock",
            simulated=True,
            ra_deg=request.hint_ra_deg if request.hint_ra_deg is not None else 83.8221,
            dec_deg=request.hint_dec_deg if request.hint_dec_deg is not None else -5.3911,
            rotation_deg=0.0,
            pixel_scale_arcsec=42.0,
            field_width_deg=40.0,
            field_height_deg=24.0,
            detail="模拟板解析结果，仅用于无 astrometry.net 环境的接口联调",
        )


def build_plate_solver(settings: Settings, runner: CommandRunner | None = None) -> PlateSolver:
    if settings.plate_solver_backend not in {"auto", "astrometry", "mock"}:
        raise ValueError("STARFINDING_PLATE_SOLVER_BACKEND 仅支持 auto、astrometry 或 mock")
    if settings.plate_solver_backend == "mock":
        return MockPlateSolver()
    real = AstrometryNetSolver(settings, runner)
    if settings.plate_solver_backend == "astrometry":
        return real
    if real.available:
        return real
    if not settings.allow_mock_fallback:
        return real
    return MockPlateSolver()
