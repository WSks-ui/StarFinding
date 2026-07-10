from __future__ import annotations

import asyncio
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, AsyncIterator

from fastapi import FastAPI, File, Header, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect, status
from fastapi.responses import FileResponse

from . import __version__
from .camera import build_camera
from .commands import CommandRunner
from .config import Settings
from .database import Database
from .models import (
    CaptureRequest,
    CameraCapabilities,
    CameraStatus,
    FileRecord,
    PlateSolveRequest,
    StackRequest,
    TERMINAL_STATUSES,
    TaskRecord,
    TaskType,
    TimelapseRequest,
)
from .plate_solver import build_plate_solver
from .task_manager import TaskManager
from .timelapse import TimelapseEncoder


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    settings.prepare()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        runner = CommandRunner()
        database = Database(settings.database_path)
        database.initialize()
        camera = build_camera(settings, runner)
        plate_solver = build_plate_solver(settings, runner)
        timelapse = TimelapseEncoder(settings, runner)
        manager = TaskManager(settings, database, camera, plate_solver, timelapse)
        app.state.settings = settings
        app.state.database = database
        app.state.camera = camera
        app.state.plate_solver = plate_solver
        app.state.timelapse = timelapse
        app.state.task_manager = manager
        await manager.start()
        try:
            yield
        finally:
            await manager.stop()

    app = FastAPI(
        title="StarFinding Camera Gateway",
        version=__version__,
        description="EOS R7、板解析、星空堆栈和延时视频的树莓派本地网关",
        lifespan=lifespan,
    )

    @app.get("/", include_in_schema=False)
    async def root() -> dict[str, str]:
        return {"service": "StarFinding Camera Gateway", "version": __version__, "docs": "/docs"}

    @app.get("/health")
    async def health() -> dict[str, object]:
        camera_status = await asyncio.to_thread(app.state.camera.status)
        return {
            "status": "ok",
            "version": __version__,
            "camera": camera_status.model_dump(),
            "plate_solver": {
                "backend": app.state.plate_solver.backend_name,
                "simulated": app.state.plate_solver.backend_name == "mock",
            },
            "ffmpeg": {
                "available": app.state.timelapse.available,
                "binary": settings.ffmpeg_binary,
            },
            "database": "ok",
        }

    @app.get("/camera/status", include_in_schema=False)
    @app.get("/api/v1/camera/status")
    async def camera_status() -> CameraStatus:
        return await asyncio.to_thread(app.state.camera.status)

    @app.get("/camera/capabilities", include_in_schema=False)
    @app.get("/api/v1/camera/capabilities")
    async def camera_capabilities() -> CameraCapabilities:
        return await asyncio.to_thread(app.state.camera.capabilities)

    @app.get("/liveview", response_class=FileResponse, include_in_schema=False)
    @app.get("/api/v1/camera/liveview", response_class=FileResponse)
    async def camera_liveview() -> FileResponse:
        path = settings.data_dir / "previews" / "latest.jpg"
        try:
            result = await asyncio.to_thread(app.state.camera.liveview, path)
        except Exception as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        return FileResponse(result, media_type="image/jpeg", headers={"Cache-Control": "no-store"})

    async def submit_task(
        task_type: TaskType,
        payload: dict[str, object],
        idempotency_key: str | None,
    ) -> TaskRecord:
        if idempotency_key is not None and not (1 <= len(idempotency_key) <= 128):
            raise HTTPException(status_code=400, detail="Idempotency-Key 长度必须为 1–128")
        try:
            task, _created = await app.state.task_manager.submit(task_type, payload, idempotency_key)
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        return task

    @app.post(
        "/capture/tasks",
        response_model=TaskRecord,
        status_code=status.HTTP_202_ACCEPTED,
        include_in_schema=False,
    )
    @app.post("/api/v1/capture/tasks", response_model=TaskRecord, status_code=status.HTTP_202_ACCEPTED)
    async def create_capture_task(
        request: CaptureRequest,
        idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> TaskRecord:
        return await submit_task(TaskType.CAPTURE, request.model_dump(), idempotency_key)

    @app.post(
        "/plate-solve",
        response_model=TaskRecord,
        status_code=status.HTTP_202_ACCEPTED,
        include_in_schema=False,
    )
    @app.post("/api/v1/plate-solve", response_model=TaskRecord, status_code=status.HTTP_202_ACCEPTED)
    async def create_plate_solve_task(
        request: PlateSolveRequest,
        idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> TaskRecord:
        return await submit_task(TaskType.PLATE_SOLVE, request.model_dump(), idempotency_key)

    @app.post("/stack", response_model=TaskRecord, status_code=status.HTTP_202_ACCEPTED, include_in_schema=False)
    @app.post("/api/v1/stack", response_model=TaskRecord, status_code=status.HTTP_202_ACCEPTED)
    async def create_stack_task(
        request: StackRequest,
        idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> TaskRecord:
        return await submit_task(TaskType.STACK, request.model_dump(), idempotency_key)

    @app.post(
        "/timelapse",
        response_model=TaskRecord,
        status_code=status.HTTP_202_ACCEPTED,
        include_in_schema=False,
    )
    @app.post("/api/v1/timelapse", response_model=TaskRecord, status_code=status.HTTP_202_ACCEPTED)
    async def create_timelapse_task(
        request: TimelapseRequest,
        idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> TaskRecord:
        return await submit_task(TaskType.TIMELAPSE, request.model_dump(), idempotency_key)

    @app.get("/tasks", response_model=list[TaskRecord], include_in_schema=False)
    @app.get("/api/v1/tasks", response_model=list[TaskRecord])
    async def list_tasks(limit: int = Query(default=50, ge=1, le=200)) -> list[TaskRecord]:
        return app.state.database.list_tasks(limit=limit)

    @app.get("/tasks/{task_id}", response_model=TaskRecord, include_in_schema=False)
    @app.get("/api/v1/tasks/{task_id}", response_model=TaskRecord)
    async def get_task(task_id: str) -> TaskRecord:
        task = app.state.database.get_task(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="任务不存在")
        return task

    @app.post("/tasks/{task_id}/cancel", response_model=TaskRecord, include_in_schema=False)
    @app.post("/api/v1/tasks/{task_id}/cancel", response_model=TaskRecord)
    async def cancel_task(task_id: str) -> TaskRecord:
        try:
            return await app.state.task_manager.cancel(task_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail="任务不存在") from exc

    @app.post(
        "/files",
        response_model=FileRecord,
        status_code=status.HTTP_201_CREATED,
        include_in_schema=False,
    )
    @app.post("/api/v1/files", response_model=FileRecord, status_code=status.HTTP_201_CREATED)
    async def upload_file(file: Annotated[UploadFile, File(description="待板解析、堆栈或制片的 JPEG/PNG")]) -> FileRecord:
        original_name = Path(file.filename or "upload.jpg").name
        suffix = Path(original_name).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png"}:
            raise HTTPException(status_code=415, detail="仅支持 JPEG 或 PNG 上传")
        target_dir = settings.data_dir / "captures" / "uploads"
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{uuid.uuid4()}{suffix}"
        size = 0
        try:
            with target.open("wb") as output:
                while chunk := await file.read(1024 * 1024):
                    size += len(chunk)
                    if size > settings.max_upload_bytes:
                        raise HTTPException(status_code=413, detail="上传文件超过大小限制")
                    output.write(chunk)
            # Pillow 解码由实际处理任务完成，这里至少拒绝空文件，且文件名不参与路径拼接。
            if size == 0:
                raise HTTPException(status_code=400, detail="上传文件为空")
            mime = "image/png" if suffix == ".png" else "image/jpeg"
            return app.state.database.register_file(target, task_id=None, kind="upload", mime_type=mime)
        except Exception:
            target.unlink(missing_ok=True)
            raise
        finally:
            await file.close()

    @app.get("/files", response_model=list[FileRecord], include_in_schema=False)
    @app.get("/api/v1/files", response_model=list[FileRecord])
    async def list_files(
        task_id: str | None = None,
        limit: int = Query(default=100, ge=1, le=500),
    ) -> list[FileRecord]:
        return app.state.database.list_files(task_id=task_id, limit=limit)

    @app.get("/files/{file_id}", response_class=FileResponse, include_in_schema=False)
    @app.get("/api/v1/files/{file_id}", response_class=FileResponse)
    async def download_file(file_id: str) -> FileResponse:
        record = app.state.database.get_file(file_id)
        path = app.state.database.get_file_path(file_id)
        if record is None or path is None:
            raise HTTPException(status_code=404, detail="文件不存在")
        resolved = path.resolve()
        if not resolved.is_relative_to(settings.data_dir) or not resolved.is_file():
            raise HTTPException(status_code=410, detail="文件记录存在，但磁盘文件不可用")
        return FileResponse(resolved, media_type=record.mime_type, filename=record.name)

    @app.websocket("/ws/tasks/{task_id}")
    async def task_progress(websocket: WebSocket, task_id: str) -> None:
        await websocket.accept()
        task = app.state.database.get_task(task_id)
        if task is None:
            await websocket.close(code=4404, reason="任务不存在")
            return
        queue = app.state.task_manager.subscribe(task_id)
        try:
            await websocket.send_json(task.model_dump(mode="json"))
            if task.status in TERMINAL_STATUSES:
                await websocket.close(code=1000)
                return
            while True:
                updated = await queue.get()
                await websocket.send_json(updated.model_dump(mode="json"))
                if updated.status in TERMINAL_STATUSES:
                    await websocket.close(code=1000)
                    return
        except WebSocketDisconnect:
            return
        finally:
            app.state.task_manager.unsubscribe(task_id, queue)

    return app


app = create_app()
