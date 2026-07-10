from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from pathlib import Path
from typing import Any

from .models import FileRecord, TaskRecord, TaskStatus, TaskType, utc_now_iso


class Database:
    """线程安全的轻量 SQLite 存储。

    FastAPI 的异步任务会把相机和图像工作放入线程池，因此这里用独立短连接，
    同时以锁保护建表和写事务。WAL 模式允许 Pad 查询进度时不阻塞后台写入。
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self._write_lock = threading.RLock()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=15, check_same_thread=False)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 15000")
        return connection

    def initialize(self) -> None:
        with self._write_lock, self._connect() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    status TEXT NOT NULL,
                    progress INTEGER NOT NULL DEFAULT 0,
                    message TEXT NOT NULL DEFAULT '',
                    input_json TEXT NOT NULL,
                    output_json TEXT,
                    error TEXT,
                    idempotency_key TEXT UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);

                CREATE TABLE IF NOT EXISTS files (
                    id TEXT PRIMARY KEY,
                    task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                    path TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_files_task_id ON files(task_id);
                """
            )

    def recover_interrupted_tasks(self) -> None:
        now = utc_now_iso()
        with self._write_lock, self._connect() as connection:
            connection.execute(
                """UPDATE tasks
                   SET status = ?, error = ?, message = ?, updated_at = ?
                   WHERE status = ?""",
                (
                    TaskStatus.FAILED,
                    "网关进程在任务执行期间重启",
                    "任务因网关重启而中断，可由 Pad 重新提交",
                    now,
                    TaskStatus.RUNNING,
                ),
            )

    def create_task(
        self,
        task_type: TaskType,
        payload: dict[str, Any],
        idempotency_key: str | None = None,
    ) -> tuple[TaskRecord, bool]:
        if idempotency_key:
            existing = self.find_task_by_idempotency_key(idempotency_key)
            if existing:
                return existing, False

        task_id = str(uuid.uuid4())
        now = utc_now_iso()
        try:
            with self._write_lock, self._connect() as connection:
                connection.execute(
                    """INSERT INTO tasks
                       (id, type, status, progress, message, input_json, idempotency_key, created_at, updated_at)
                       VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)""",
                    (
                        task_id,
                        task_type,
                        TaskStatus.PENDING,
                        "任务已进入队列",
                        json.dumps(payload, ensure_ascii=False),
                        idempotency_key,
                        now,
                        now,
                    ),
                )
        except sqlite3.IntegrityError:
            if idempotency_key and (existing := self.find_task_by_idempotency_key(idempotency_key)):
                return existing, False
            raise
        task = self.get_task(task_id)
        assert task is not None
        return task, True

    def find_task_by_idempotency_key(self, key: str) -> TaskRecord | None:
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM tasks WHERE idempotency_key = ?", (key,)).fetchone()
        return self._task_from_row(row) if row else None

    def get_task(self, task_id: str) -> TaskRecord | None:
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        return self._task_from_row(row) if row else None

    def list_tasks(self, *, limit: int = 50) -> list[TaskRecord]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM tasks ORDER BY created_at DESC LIMIT ?", (max(1, min(limit, 200)),)
            ).fetchall()
        return [self._task_from_row(row) for row in rows]

    def list_pending_task_ids(self) -> list[str]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT id FROM tasks WHERE status = ? ORDER BY created_at", (TaskStatus.PENDING,)
            ).fetchall()
        return [str(row["id"]) for row in rows]

    def update_task(
        self,
        task_id: str,
        *,
        status: TaskStatus | None = None,
        progress: int | None = None,
        message: str | None = None,
        output: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> TaskRecord:
        current = self.get_task(task_id)
        if current is None:
            raise KeyError(task_id)
        fields: dict[str, Any] = {"updated_at": utc_now_iso()}
        if status is not None:
            fields["status"] = str(status)
        if progress is not None:
            fields["progress"] = max(0, min(int(progress), 100))
        if message is not None:
            fields["message"] = message
        if output is not None:
            fields["output_json"] = json.dumps(output, ensure_ascii=False)
        if error is not None:
            fields["error"] = error
        assignments = ", ".join(f"{key} = ?" for key in fields)
        with self._write_lock, self._connect() as connection:
            connection.execute(
                f"UPDATE tasks SET {assignments} WHERE id = ?",
                (*fields.values(), task_id),
            )
        updated = self.get_task(task_id)
        assert updated is not None
        return updated

    def register_file(self, path: Path, *, task_id: str | None, kind: str, mime_type: str) -> FileRecord:
        resolved = path.resolve()
        file_id = str(uuid.uuid4())
        now = utc_now_iso()
        with self._write_lock, self._connect() as connection:
            existing = connection.execute("SELECT * FROM files WHERE path = ?", (str(resolved),)).fetchone()
            if existing:
                return self._file_from_row(existing)
            connection.execute(
                """INSERT INTO files (id, task_id, path, name, mime_type, size, kind, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (file_id, task_id, str(resolved), resolved.name, mime_type, resolved.stat().st_size, kind, now),
            )
        record = self.get_file(file_id)
        assert record is not None
        return record

    def get_file(self, file_id: str) -> FileRecord | None:
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM files WHERE id = ?", (file_id,)).fetchone()
        return self._file_from_row(row) if row else None

    def get_file_path(self, file_id: str) -> Path | None:
        with self._connect() as connection:
            row = connection.execute("SELECT path FROM files WHERE id = ?", (file_id,)).fetchone()
        return Path(row["path"]) if row else None

    def list_files(self, *, task_id: str | None = None, limit: int = 100) -> list[FileRecord]:
        with self._connect() as connection:
            if task_id:
                rows = connection.execute(
                    "SELECT * FROM files WHERE task_id = ? ORDER BY created_at DESC LIMIT ?",
                    (task_id, max(1, min(limit, 500))),
                ).fetchall()
            else:
                rows = connection.execute(
                    "SELECT * FROM files ORDER BY created_at DESC LIMIT ?", (max(1, min(limit, 500)),)
                ).fetchall()
        return [self._file_from_row(row) for row in rows]

    @staticmethod
    def _task_from_row(row: sqlite3.Row) -> TaskRecord:
        return TaskRecord(
            id=row["id"],
            type=row["type"],
            status=row["status"],
            progress=row["progress"],
            message=row["message"],
            input=json.loads(row["input_json"]),
            output=json.loads(row["output_json"]) if row["output_json"] else None,
            error=row["error"],
            idempotency_key=row["idempotency_key"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    @staticmethod
    def _file_from_row(row: sqlite3.Row) -> FileRecord:
        return FileRecord(
            id=row["id"],
            task_id=row["task_id"],
            name=row["name"],
            mime_type=row["mime_type"],
            size=row["size"],
            kind=row["kind"],
            created_at=row["created_at"],
        )
