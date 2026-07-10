from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(slots=True)
class Settings:
    """网关运行配置。

    所有路径在启动时转为绝对路径，避免 systemd 与命令行使用不同工作目录时，
    把相片或数据库写入不可预期的位置。
    """

    data_dir: Path = Path("data")
    database_path: Path | None = None
    camera_backend: str = "auto"
    plate_solver_backend: str = "auto"
    ffmpeg_binary: str = "ffmpeg"
    gphoto2_binary: str = "gphoto2"
    solve_field_binary: str = "solve-field"
    command_timeout_seconds: float = 45.0
    capture_timeout_seconds: float = 360.0
    max_upload_bytes: int = 80 * 1024 * 1024
    worker_count: int = 1
    mock_seed: int = 20260726
    allow_mock_fallback: bool = True

    @classmethod
    def from_env(cls) -> "Settings":
        data_dir = Path(os.getenv("STARFINDING_DATA_DIR", "data")).expanduser().resolve()
        db_value = os.getenv("STARFINDING_DATABASE_PATH")
        return cls(
            data_dir=data_dir,
            database_path=Path(db_value).expanduser().resolve() if db_value else None,
            camera_backend=os.getenv("STARFINDING_CAMERA_BACKEND", "auto").lower(),
            plate_solver_backend=os.getenv("STARFINDING_PLATE_SOLVER_BACKEND", "auto").lower(),
            ffmpeg_binary=os.getenv("STARFINDING_FFMPEG", "ffmpeg"),
            gphoto2_binary=os.getenv("STARFINDING_GPHOTO2", "gphoto2"),
            solve_field_binary=os.getenv("STARFINDING_SOLVE_FIELD", "solve-field"),
            command_timeout_seconds=float(os.getenv("STARFINDING_COMMAND_TIMEOUT", "45")),
            capture_timeout_seconds=float(os.getenv("STARFINDING_CAPTURE_TIMEOUT", "360")),
            max_upload_bytes=int(os.getenv("STARFINDING_MAX_UPLOAD_BYTES", str(80 * 1024 * 1024))),
            worker_count=max(1, int(os.getenv("STARFINDING_WORKERS", "1"))),
            mock_seed=int(os.getenv("STARFINDING_MOCK_SEED", "20260726")),
            allow_mock_fallback=_env_bool("STARFINDING_ALLOW_MOCK_FALLBACK", True),
        )

    def prepare(self) -> None:
        self.data_dir = self.data_dir.expanduser().resolve()
        if self.database_path is None:
            self.database_path = self.data_dir / "gateway.sqlite3"
        else:
            self.database_path = self.database_path.expanduser().resolve()

        for child in ("captures", "processed", "videos", "previews", "work"):
            (self.data_dir / child).mkdir(parents=True, exist_ok=True)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
