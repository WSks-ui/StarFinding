"""服务配置，只从环境变量读取部署参数和密钥。"""

from __future__ import annotations

import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    data_dir: Path = field(
        default_factory=lambda: Path(
            os.getenv(
                "STARFINDING_DATA_DIR",
                str(Path(tempfile.gettempdir()) / "starfinding-cloud"),
            )
        )
    )
    backend: str = field(
        default_factory=lambda: os.getenv("ENHANCEMENT_BACKEND", "auto").lower()
    )
    max_upload_mb: int = field(
        default_factory=lambda: int(os.getenv("MAX_UPLOAD_MB", "40"))
    )
    modelarts_enabled: bool = field(
        default_factory=lambda: _as_bool(os.getenv("MODELARTS_ENABLED"), False)
    )
    modelarts_endpoint: str = field(
        default_factory=lambda: os.getenv("MODELARTS_ENDPOINT", "").strip()
    )
    modelarts_token: str = field(
        default_factory=lambda: os.getenv("MODELARTS_TOKEN", "").strip()
    )
    modelarts_auth_header: str = field(
        default_factory=lambda: os.getenv(
            "MODELARTS_AUTH_HEADER", "X-Auth-Token"
        ).strip()
    )
    modelarts_timeout_seconds: float = field(
        default_factory=lambda: float(os.getenv("MODELARTS_TIMEOUT_SECONDS", "20"))
    )
    obs_endpoint: str = field(
        default_factory=lambda: os.getenv("OBS_ENDPOINT", "").strip()
    )
    obs_access_key_id: str = field(
        default_factory=lambda: os.getenv("OBS_ACCESS_KEY_ID", "").strip()
    )
    obs_secret_access_key: str = field(
        default_factory=lambda: os.getenv("OBS_SECRET_ACCESS_KEY", "").strip()
    )
    obs_bucket: str = field(
        default_factory=lambda: os.getenv("OBS_BUCKET", "").strip()
    )

    def validate(self) -> None:
        if self.backend not in {"auto", "local", "mock", "modelarts"}:
            raise ValueError(
                "ENHANCEMENT_BACKEND 必须是 auto/local/mock/modelarts 之一"
            )
        if self.max_upload_mb < 1 or self.max_upload_mb > 500:
            raise ValueError("MAX_UPLOAD_MB 必须在 1 到 500 之间")
        if not re.fullmatch(r"[A-Za-z0-9-]+", self.modelarts_auth_header):
            raise ValueError("MODELARTS_AUTH_HEADER 不是合法的 HTTP 请求头名称")

    @property
    def modelarts_configured(self) -> bool:
        return bool(
            self.modelarts_enabled
            and self.modelarts_endpoint
            and self.modelarts_token
        )

    @property
    def obs_configured(self) -> bool:
        return bool(
            self.obs_endpoint
            and self.obs_access_key_id
            and self.obs_secret_access_key
            and self.obs_bucket
        )
