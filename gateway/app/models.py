from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class TaskType(StrEnum):
    CAPTURE = "capture"
    PLATE_SOLVE = "plate_solve"
    STACK = "stack"
    TIMELAPSE = "timelapse"


class TaskStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"


TERMINAL_STATUSES = {TaskStatus.SUCCEEDED, TaskStatus.FAILED, TaskStatus.CANCELLED}


class CameraStatus(BaseModel):
    connected: bool
    backend: Literal["gphoto2", "mock"]
    simulated: bool
    model: str | None = None
    battery: str | None = None
    detail: str | None = None


class CameraCapabilities(BaseModel):
    backend: Literal["gphoto2", "mock"]
    liveview: bool = True
    raw_jpeg: bool = True
    bulb: bool = False
    max_exposure_seconds: float = 30.0
    iso_values: list[str] = Field(default_factory=list)
    aperture_values: list[str] = Field(default_factory=list)
    shutter_values: list[str] = Field(default_factory=list)


class CaptureRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    iso: str = Field(default="800", pattern=r"^[A-Za-z0-9 .+/-]{1,24}$")
    aperture: str = Field(default="4", pattern=r"^[A-Za-z0-9 .+/-]{1,24}$")
    exposure_seconds: float = Field(default=10.0, gt=0, le=300)
    count: int = Field(default=1, ge=1, le=500)
    interval_seconds: float = Field(default=0.0, ge=0, le=3600)
    raw_jpeg: bool = True
    label: str = Field(default="capture", min_length=1, max_length=40, pattern=r"^[A-Za-z0-9_-]+$")


class PlateSolveRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    file_id: str
    hint_ra_deg: float | None = Field(default=None, ge=0, lt=360)
    hint_dec_deg: float | None = Field(default=None, ge=-90, le=90)
    search_radius_deg: float = Field(default=20.0, gt=0, le=180)
    pixel_scale_low: float | None = Field(default=None, gt=0)
    pixel_scale_high: float | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_scale(self) -> "PlateSolveRequest":
        if (self.pixel_scale_low is None) != (self.pixel_scale_high is None):
            raise ValueError("像素尺度上下限必须同时提供")
        if self.pixel_scale_low is not None and self.pixel_scale_low >= self.pixel_scale_high:
            raise ValueError("像素尺度下限必须小于上限")
        return self


class StackRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    file_ids: list[str] = Field(min_length=2, max_length=200)
    reject_bad_frames: bool = True
    correct_light_pollution: bool = True
    output_format: Literal["jpeg", "png"] = "jpeg"

    @field_validator("file_ids")
    @classmethod
    def distinct_files(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("堆栈文件不能重复")
        return value


class TimelapseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    file_ids: list[str] = Field(min_length=2, max_length=2000)
    fps: int = Field(default=24, ge=1, le=60)
    width: int = Field(default=1920, ge=320, le=4096)
    height: int = Field(default=1080, ge=240, le=2160)

    @field_validator("width", "height")
    @classmethod
    def require_even_dimension(cls, value: int) -> int:
        if value % 2:
            raise ValueError("H.264 yuv420p 视频宽高必须为偶数")
        return value


class TaskRecord(BaseModel):
    id: str
    type: TaskType
    status: TaskStatus
    progress: int = Field(ge=0, le=100)
    message: str
    input: dict[str, Any]
    output: dict[str, Any] | None = None
    error: str | None = None
    idempotency_key: str | None = None
    created_at: str
    updated_at: str


class FileRecord(BaseModel):
    id: str
    task_id: str | None = None
    name: str
    mime_type: str
    size: int
    kind: str
    created_at: str


class PlateSolveResult(BaseModel):
    solved: bool
    backend: Literal["astrometry.net", "mock"]
    simulated: bool
    ra_deg: float | None = None
    dec_deg: float | None = None
    rotation_deg: float | None = None
    pixel_scale_arcsec: float | None = None
    field_width_deg: float | None = None
    field_height_deg: float | None = None
    detail: str | None = None
