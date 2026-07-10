"""使用 JSON 文件持久化任务，便于树莓派和容器重启后继续查询。"""

from __future__ import annotations

import json
import threading
from copy import deepcopy
from pathlib import Path
from typing import Any


class TaskRepository:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir.resolve()
        self.tasks_dir = self.data_dir / "tasks"
        self.tasks_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def task_dir(self, task_id: str) -> Path:
        # task_id 在 API 层已校验为 UUID，这里仍使用 resolve 防止未来调用者造成目录穿越。
        path = (self.tasks_dir / task_id).resolve()
        if self.tasks_dir not in path.parents:
            raise ValueError("非法任务目录")
        path.mkdir(parents=True, exist_ok=True)
        return path

    def get(self, task_id: str) -> dict[str, Any] | None:
        metadata_path = self.task_dir(task_id) / "metadata.json"
        with self._lock:
            if not metadata_path.exists():
                return None
            return json.loads(metadata_path.read_text(encoding="utf-8"))

    def save(self, record: dict[str, Any]) -> dict[str, Any]:
        task_id = str(record["task_id"])
        metadata_path = self.task_dir(task_id) / "metadata.json"
        temporary_path = metadata_path.with_suffix(".json.tmp")
        with self._lock:
            temporary_path.write_text(
                json.dumps(record, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            temporary_path.replace(metadata_path)
        return deepcopy(record)

    def update(self, task_id: str, **changes: Any) -> dict[str, Any]:
        with self._lock:
            record = self.get(task_id)
            if record is None:
                raise KeyError(task_id)
            record.update(changes)
            return self.save(record)
