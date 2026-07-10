"""增强任务编排。"""

from __future__ import annotations

import hashlib
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from .config import Settings
from .image_processing import decode_image
from .providers import EnhancementProvider
from .repository import TaskRepository
from .schemas import TaskState


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


class EnhancementService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repository = TaskRepository(settings.data_dir)
        self.provider = EnhancementProvider(settings)
        # R7 全分辨率图约占数百 MB；单进程内串行处理，避免并发任务叠加导致树莓派内存不足。
        self._processing_lock = threading.Lock()

    @staticmethod
    def normalize_task_id(task_id: str | None) -> str:
        if task_id is None or not task_id.strip():
            return str(uuid4())
        return str(UUID(task_id.strip()))

    def create_task(
        self,
        content: bytes,
        task_id: str | None,
        strength: float,
    ) -> tuple[dict[str, Any], bool]:
        normalized_id = self.normalize_task_id(task_id)
        input_hash = sha256(content)
        existing = self.repository.get(normalized_id)
        if existing is not None:
            if existing["input_sha256"] != input_hash:
                raise FileExistsError("同一 task_id 已绑定另一张原图")
            return existing, False

        image, image_format = decode_image(content)
        task_dir = self.repository.task_dir(normalized_id)
        suffix = {"JPEG": ".jpg", "PNG": ".png", "WEBP": ".webp"}.get(
            image_format, ".img"
        )
        original_name = f"original{suffix}"
        (task_dir / original_name).write_bytes(content)

        now = utc_now()
        record: dict[str, Any] = {
            "task_id": normalized_id,
            "state": TaskState.PENDING.value,
            "created_at": now,
            "updated_at": now,
            "requested_backend": self.settings.backend,
            "backend_used": None,
            "input_sha256": input_hash,
            "output_sha256": None,
            "original_file": original_name,
            "result_file": None,
            "mask_file": None,
            "error": None,
            "fallback_reason": None,
            "processing": {
                "strength": strength,
                "input_format": image_format,
                "width": image.width,
                "height": image.height,
            },
        }
        return self.repository.save(record), True

    def run_task(self, task_id: str) -> None:
        with self._processing_lock:
            self._run_task_locked(task_id)

    def _run_task_locked(self, task_id: str) -> None:
        record = self.repository.get(task_id)
        if record is None or record["state"] != TaskState.PENDING.value:
            return
        self.repository.update(
            task_id,
            state=TaskState.RUNNING.value,
            updated_at=utc_now(),
        )

        task_dir = self.repository.task_dir(task_id)
        original_path = task_dir / record["original_file"]
        original_bytes = original_path.read_bytes()
        try:
            original, _ = decode_image(original_bytes)
            result, mask, stats, backend_used, fallback_reason = self.provider.enhance(
                original,
                original_bytes,
                task_id=task_id,
                strength=float(record["processing"]["strength"]),
            )
            result_path = task_dir / "result.png"
            mask_path = task_dir / "star-mask.png"
            result.save(result_path, format="PNG", compress_level=3)
            mask.save(mask_path, format="PNG", compress_level=3)
            result_bytes = result_path.read_bytes()

            processing = dict(record["processing"])
            processing.update(stats)
            self.repository.update(
                task_id,
                state=TaskState.SUCCEEDED.value,
                updated_at=utc_now(),
                backend_used=backend_used,
                result_file=result_path.name,
                mask_file=mask_path.name,
                output_sha256=sha256(result_bytes),
                fallback_reason=fallback_reason,
                processing=processing,
            )
        except Exception as exc:  # noqa: BLE001 - 后台任务必须落盘失败状态，不能静默丢失。
            self.repository.update(
                task_id,
                state=TaskState.FAILED.value,
                updated_at=utc_now(),
                error=f"{type(exc).__name__}: {exc}",
            )

    def get_task(self, task_id: str) -> dict[str, Any] | None:
        return self.repository.get(self.normalize_task_id(task_id))

    def artifact(self, task_id: str, key: str) -> Path | None:
        record = self.get_task(task_id)
        if record is None:
            return None
        file_name = record.get(key)
        if not file_name:
            return None
        path = (self.repository.task_dir(record["task_id"]) / file_name).resolve()
        if self.repository.task_dir(record["task_id"]) not in path.parents:
            return None
        return path if path.is_file() else None
