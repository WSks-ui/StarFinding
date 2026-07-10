"""本地、模拟和 ModelArts 增强后端。"""

from __future__ import annotations

import urllib.error
import urllib.request
from dataclasses import asdict
from io import BytesIO
from typing import Any

from PIL import Image

from .config import Settings
from .image_processing import (
    ALGORITHM_VERSION,
    ProcessingStats,
    detect_star_mask,
    local_candidate,
    protect_stars,
)


class ModelArtsClient:
    """调用 ModelArts 在线服务。

    服务约定：请求体为原始图像字节，响应体为增强后的图像字节。即使云端返回结果，
    本服务仍会在本地重新应用星点保护掩膜，以保证比赛演示的真实性约束。
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def enhance(self, image_bytes: bytes, task_id: str, strength: float) -> Image.Image:
        headers = {
            "Content-Type": "application/octet-stream",
            "X-StarFinding-Task-Id": task_id,
            "X-Enhancement-Strength": f"{strength:.3f}",
            self.settings.modelarts_auth_header: self.settings.modelarts_token,
        }
        request = urllib.request.Request(
            self.settings.modelarts_endpoint,
            data=image_bytes,
            method="POST",
            headers=headers,
        )
        try:
            with urllib.request.urlopen(
                request, timeout=self.settings.modelarts_timeout_seconds
            ) as response:
                content = response.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise RuntimeError(f"ModelArts 调用失败: {type(exc).__name__}") from exc

        try:
            with Image.open(BytesIO(content)) as opened:
                candidate = opened.convert("RGB")
                candidate.load()
                return candidate
        except (OSError, ValueError) as exc:
            raise RuntimeError("ModelArts 未返回有效图像") from exc


class EnhancementProvider:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.modelarts = ModelArtsClient(settings)

    def enhance(
        self,
        original: Image.Image,
        original_bytes: bytes,
        task_id: str,
        strength: float,
    ) -> tuple[Image.Image, Image.Image, dict[str, Any], str, str | None]:
        mask, threshold = detect_star_mask(original)
        requested = self.settings.backend
        fallback_reason: str | None = None

        if requested == "mock":
            candidate = original.copy()
            backend_used = "mock"
        elif requested == "local":
            candidate = local_candidate(original, strength)
            backend_used = "local"
        elif requested in {"auto", "modelarts"} and self.settings.modelarts_configured:
            try:
                candidate = self.modelarts.enhance(
                    original_bytes, task_id=task_id, strength=strength
                )
                if candidate.size != original.size:
                    raise RuntimeError("ModelArts 返回图像尺寸与原图不一致")
                backend_used = "modelarts"
            except RuntimeError as exc:
                # 云端故障不能中断比赛拍摄链路，失败后立即使用确定性的本地算法。
                candidate = local_candidate(original, strength)
                backend_used = "local_fallback"
                fallback_reason = str(exc)
        else:
            candidate = local_candidate(original, strength)
            backend_used = "local_fallback" if requested == "modelarts" else "local"
            if requested == "modelarts":
                fallback_reason = "ModelArts 未完整配置，已使用本地增强"

        protected = protect_stars(original, candidate, mask)
        mask_image = mask.convert("L")
        stats = ProcessingStats(
            algorithm_version=ALGORITHM_VERSION,
            threshold=round(threshold, 4),
            protected_pixel_ratio=round(
                float(sum(mask.histogram()[128:]) / (mask.width * mask.height)), 8
            ),
            width=original.width,
            height=original.height,
        )
        return protected, mask_image, asdict(stats), backend_used, fallback_reason
