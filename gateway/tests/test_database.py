from __future__ import annotations

from pathlib import Path

from app.database import Database
from app.models import TaskStatus, TaskType


def test_database_recovers_interrupted_task(tmp_path: Path) -> None:
    database = Database(tmp_path / "test.sqlite3")
    database.initialize()
    task, created = database.create_task(TaskType.CAPTURE, {"count": 1}, "recover-key")
    assert created is True
    database.update_task(task.id, status=TaskStatus.RUNNING, message="running")

    database.recover_interrupted_tasks()
    recovered = database.get_task(task.id)
    assert recovered is not None
    assert recovered.status == TaskStatus.FAILED
    assert "重启" in (recovered.error or "")

    same, created_again = database.create_task(TaskType.CAPTURE, {"count": 99}, "recover-key")
    assert created_again is False
    assert same.id == task.id
