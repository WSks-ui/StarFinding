from __future__ import annotations

import time
from pathlib import Path
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture()
def client(tmp_path: Path) -> Iterator[TestClient]:
    settings = Settings(
        data_dir=tmp_path / "gateway-data",
        camera_backend="mock",
        plate_solver_backend="mock",
        ffmpeg_binary="definitely-not-installed-ffmpeg",
        worker_count=1,
        mock_seed=20260726,
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def wait_for_task(client: TestClient, task_id: str, timeout: float = 15.0) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/tasks/{task_id}")
        assert response.status_code == 200
        task = response.json()
        if task["status"] in {"succeeded", "failed", "cancelled"}:
            return task
        time.sleep(0.05)
    raise AssertionError(f"任务 {task_id} 在 {timeout} 秒内未结束")
