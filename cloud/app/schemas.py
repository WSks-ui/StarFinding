"""HTTP 接口数据契约。"""

from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class TaskState(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskView(BaseModel):
    task_id: str
    state: TaskState
    created_at: str
    updated_at: str
    requested_backend: str
    backend_used: str | None = None
    input_sha256: str
    output_sha256: str | None = None
    error: str | None = None
    fallback_reason: str | None = None
    processing: dict[str, Any] = Field(default_factory=dict)
    links: dict[str, str] = Field(default_factory=dict)


class HealthView(BaseModel):
    status: str
    local_backend_ready: bool
    modelarts_configured: bool
    obs_configured: bool
