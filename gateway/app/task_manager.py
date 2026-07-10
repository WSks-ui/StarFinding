from __future__ import annotations

import asyncio
import logging
import mimetypes
import shutil
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .camera import CameraAdapter
from .config import Settings
from .database import Database
from .image_processing import stack_images
from .models import (
    CaptureRequest,
    PlateSolveRequest,
    StackRequest,
    TaskRecord,
    TaskStatus,
    TaskType,
    TimelapseRequest,
)
from .plate_solver import PlateSolver
from .timelapse import TimelapseEncoder


logger = logging.getLogger(__name__)


class TaskCancelled(RuntimeError):
    pass


def _mime_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".cr3":
        return "image/x-canon-cr3"
    if suffix == ".mp4":
        return "video/mp4"
    return mimetypes.guess_type(path.name)[0] or "application/octet-stream"


class TaskManager:
    """持久化后台任务调度器。

    worker_count 默认固定为 1，确保 R7 不会收到并发命令。图像处理同样排队执行，
    避免树莓派 5 在拍摄时被 FFT、模糊滤波或视频编码抢满内存与 CPU。
    """

    def __init__(
        self,
        settings: Settings,
        database: Database,
        camera: CameraAdapter,
        plate_solver: PlateSolver,
        timelapse: TimelapseEncoder,
    ) -> None:
        self.settings = settings
        self.database = database
        self.camera = camera
        self.plate_solver = plate_solver
        self.timelapse = timelapse
        self._queue: asyncio.Queue[str] = asyncio.Queue()
        self._workers: list[asyncio.Task[None]] = []
        self._cancel_requested: set[str] = set()
        self._subscribers: dict[str, set[asyncio.Queue[TaskRecord]]] = defaultdict(set)
        self._loop: asyncio.AbstractEventLoop | None = None

    async def start(self) -> None:
        self._loop = asyncio.get_running_loop()
        self.database.recover_interrupted_tasks()
        for task_id in self.database.list_pending_task_ids():
            await self._queue.put(task_id)
        self._workers = [
            asyncio.create_task(self._worker(index), name=f"gateway-worker-{index}")
            for index in range(self.settings.worker_count)
        ]

    async def stop(self) -> None:
        for worker in self._workers:
            worker.cancel()
        await asyncio.gather(*self._workers, return_exceptions=True)
        self._workers.clear()

    async def submit(
        self,
        task_type: TaskType,
        payload: dict[str, Any],
        idempotency_key: str | None = None,
    ) -> tuple[TaskRecord, bool]:
        task, created = self.database.create_task(task_type, payload, idempotency_key)
        if not created and task.type != task_type:
            raise ValueError("该 Idempotency-Key 已被另一类任务使用")
        if created:
            await self._queue.put(task.id)
            self._publish(task)
        return task, created

    async def cancel(self, task_id: str) -> TaskRecord:
        task = self.database.get_task(task_id)
        if task is None:
            raise KeyError(task_id)
        if task.status in {TaskStatus.SUCCEEDED, TaskStatus.FAILED, TaskStatus.CANCELLED}:
            return task
        self._cancel_requested.add(task_id)
        if task.status == TaskStatus.PENDING:
            task = self.database.update_task(
                task_id,
                status=TaskStatus.CANCELLED,
                message="任务已取消",
                progress=task.progress,
            )
            self._publish(task)
        return task

    def subscribe(self, task_id: str) -> asyncio.Queue[TaskRecord]:
        queue: asyncio.Queue[TaskRecord] = asyncio.Queue(maxsize=20)
        self._subscribers[task_id].add(queue)
        return queue

    def unsubscribe(self, task_id: str, queue: asyncio.Queue[TaskRecord]) -> None:
        queues = self._subscribers.get(task_id)
        if queues:
            queues.discard(queue)
            if not queues:
                self._subscribers.pop(task_id, None)

    def _publish(self, task: TaskRecord) -> None:
        for queue in tuple(self._subscribers.get(task.id, ())):
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            queue.put_nowait(task)

    def _publish_current(self, task_id: str) -> None:
        task = self.database.get_task(task_id)
        if task:
            self._publish(task)

    def _thread_progress(self, task_id: str, value: int, message: str) -> None:
        if task_id in self._cancel_requested:
            raise TaskCancelled("任务已由用户取消")
        current = self.database.get_task(task_id)
        if current is None or current.status != TaskStatus.RUNNING:
            return
        self.database.update_task(task_id, progress=value, message=message)
        if self._loop:
            self._loop.call_soon_threadsafe(self._publish_current, task_id)

    async def _set_progress(self, task_id: str, value: int, message: str) -> None:
        if task_id in self._cancel_requested:
            raise TaskCancelled("任务已由用户取消")
        task = self.database.update_task(task_id, progress=value, message=message)
        self._publish(task)

    async def _worker(self, _index: int) -> None:
        while True:
            task_id = await self._queue.get()
            try:
                task = self.database.get_task(task_id)
                if task is None or task.status != TaskStatus.PENDING:
                    continue
                if task_id in self._cancel_requested:
                    continue
                task = self.database.update_task(
                    task_id,
                    status=TaskStatus.RUNNING,
                    progress=1,
                    message="任务开始执行",
                )
                self._publish(task)
                output = await self._dispatch(task)
                if task_id in self._cancel_requested:
                    raise TaskCancelled("任务已由用户取消")
                task = self.database.update_task(
                    task_id,
                    status=TaskStatus.SUCCEEDED,
                    progress=100,
                    message="任务完成",
                    output=output,
                )
                self._publish(task)
            except TaskCancelled as exc:
                task = self.database.update_task(
                    task_id,
                    status=TaskStatus.CANCELLED,
                    message=str(exc),
                )
                self._publish(task)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                # 对客户端隐藏完整堆栈，只传递有限长度错误；完整信息写入 systemd 日志，
                # 便于比赛前追查 USB、板解析索引或 FFmpeg 环境问题。
                logger.exception("后台任务执行失败：%s", task_id)
                message = str(exc).strip() or exc.__class__.__name__
                task = self.database.update_task(
                    task_id,
                    status=TaskStatus.FAILED,
                    message="任务执行失败",
                    error=message[-1600:],
                )
                self._publish(task)
            finally:
                self._cancel_requested.discard(task_id)
                self._queue.task_done()

    async def _dispatch(self, task: TaskRecord) -> dict[str, Any]:
        if task.type == TaskType.CAPTURE:
            return await self._capture(task)
        if task.type == TaskType.PLATE_SOLVE:
            return await self._plate_solve(task)
        if task.type == TaskType.STACK:
            return await self._stack(task)
        if task.type == TaskType.TIMELAPSE:
            return await self._timelapse(task)
        raise ValueError(f"不支持的任务类型：{task.type}")

    async def _capture(self, task: TaskRecord) -> dict[str, Any]:
        request = CaptureRequest.model_validate(task.input)
        output_dir = self.settings.data_dir / "captures" / task.id
        output_dir.mkdir(parents=True, exist_ok=True)
        records = []
        for index in range(request.count):
            await self._set_progress(
                task.id,
                2 + int(88 * index / request.count),
                f"正在拍摄第 {index + 1}/{request.count} 帧",
            )
            paths = await asyncio.to_thread(self.camera.capture, request, output_dir, index + 1)
            for path in paths:
                suffixes = [suffix.lower() for suffix in path.suffixes]
                kind = "raw" if ".cr3" in suffixes else "capture"
                records.append(
                    self.database.register_file(path, task_id=task.id, kind=kind, mime_type=_mime_type(path))
                )
            await self._set_progress(
                task.id,
                2 + int(88 * (index + 1) / request.count),
                f"已完成第 {index + 1}/{request.count} 帧",
            )
            if index + 1 < request.count and request.interval_seconds:
                try:
                    await asyncio.wait_for(self._wait_for_cancel(task.id), timeout=request.interval_seconds)
                except TimeoutError:
                    pass
        return {
            "files": [record.model_dump() for record in records],
            "captured_frames": request.count,
            "backend": self.camera.backend_name,
            "simulated": self.camera.backend_name == "mock",
        }

    async def _wait_for_cancel(self, task_id: str) -> None:
        while task_id not in self._cancel_requested:
            await asyncio.sleep(0.1)
        raise TaskCancelled("任务已由用户取消")

    def _resolve_files(self, file_ids: list[str], *, image_only: bool = True) -> list[Path]:
        paths: list[Path] = []
        for file_id in file_ids:
            path = self.database.get_file_path(file_id)
            if path is None:
                raise ValueError(f"文件不存在：{file_id}")
            if not path.exists():
                raise ValueError(f"文件已从磁盘移除：{file_id}")
            if image_only and path.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
                raise ValueError(f"当前处理只支持 JPEG/PNG：{path.name}")
            paths.append(path)
        return paths

    async def _plate_solve(self, task: TaskRecord) -> dict[str, Any]:
        request = PlateSolveRequest.model_validate(task.input)
        image_path = self._resolve_files([request.file_id])[0]
        await self._set_progress(task.id, 10, "正在执行本地板解析")
        result = await asyncio.to_thread(
            self.plate_solver.solve,
            image_path,
            request,
            self.settings.data_dir / "work" / task.id,
        )
        if not result.solved:
            raise ValueError(result.detail or "板解析未得到解")
        await self._set_progress(task.id, 95, "板解析完成")
        return {"plate_solve": result.model_dump()}

    async def _stack(self, task: TaskRecord) -> dict[str, Any]:
        request = StackRequest.model_validate(task.input)
        paths = self._resolve_files(request.file_ids)
        suffix = ".jpg" if request.output_format == "jpeg" else ".png"
        output_path = self.settings.data_dir / "processed" / f"stack_{task.id}{suffix}"
        summary = await asyncio.to_thread(
            stack_images,
            paths,
            output_path,
            reject_bad_frames=request.reject_bad_frames,
            light_pollution=request.correct_light_pollution,
            progress=lambda value, message: self._thread_progress(task.id, value, message),
        )
        record = self.database.register_file(
            output_path,
            task_id=task.id,
            kind="stack",
            mime_type=_mime_type(output_path),
        )
        return {
            "file": record.model_dump(),
            "input_count": summary.input_count,
            "accepted_count": summary.accepted_count,
            "rejected_indices": summary.rejected_indices,
            "alignment_shifts": [list(shift) for shift in summary.shifts],
            "light_pollution_corrected": request.correct_light_pollution,
        }

    async def _timelapse(self, task: TaskRecord) -> dict[str, Any]:
        request = TimelapseRequest.model_validate(task.input)
        paths = self._resolve_files(request.file_ids)
        output_path = self.settings.data_dir / "videos" / f"timelapse_{task.id}.mp4"
        encoded = await asyncio.to_thread(
            self.timelapse.encode,
            paths,
            output_path,
            self.settings.data_dir / "work" / task.id,
            fps=request.fps,
            width=request.width,
            height=request.height,
            progress=lambda value, message: self._thread_progress(task.id, value, message),
        )
        record = self.database.register_file(encoded, task_id=task.id, kind="timelapse", mime_type="video/mp4")
        return {
            "file": record.model_dump(),
            "frame_count": len(paths),
            "fps": request.fps,
            "duration_seconds": round(len(paths) / request.fps, 3),
            "resolution": [request.width, request.height],
        }
