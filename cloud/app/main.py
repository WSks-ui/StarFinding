"""StarFinding 图像增强 HTTP 服务入口。"""

from __future__ import annotations

from typing import Annotated

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from .config import Settings
from .schemas import HealthView, TaskView
from .service import EnhancementService


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or Settings()
    resolved_settings.validate()
    service = EnhancementService(resolved_settings)

    app = FastAPI(
        title="StarFinding Constrained Enhancement API",
        version="0.1.0",
        description="保留原图并通过星点掩膜约束结果的天文图像增强服务",
    )
    app.state.settings = resolved_settings
    app.state.service = service

    def view(record: dict) -> TaskView:
        task_id = record["task_id"]
        links = {
            "self": f"/v1/enhancements/{task_id}",
            "original": f"/v1/enhancements/{task_id}/original",
        }
        if record.get("result_file"):
            links["result"] = f"/v1/enhancements/{task_id}/result"
        if record.get("mask_file"):
            links["star_mask"] = f"/v1/enhancements/{task_id}/star-mask"
        return TaskView(**record, links=links)

    @app.get("/health", response_model=HealthView)
    def health() -> HealthView:
        return HealthView(
            status="ok",
            local_backend_ready=True,
            modelarts_configured=resolved_settings.modelarts_configured,
            obs_configured=resolved_settings.obs_configured,
        )

    @app.post(
        "/v1/enhancements",
        response_model=TaskView,
        status_code=status.HTTP_202_ACCEPTED,
    )
    async def create_enhancement(
        background_tasks: BackgroundTasks,
        image: Annotated[UploadFile, File(description="JPEG、PNG 或 WebP 原图")],
        task_id: Annotated[str | None, Form()] = None,
        strength: Annotated[float, Form(ge=0.0, le=1.0)] = 0.65,
    ) -> TaskView:
        limit = resolved_settings.max_upload_mb * 1024 * 1024
        content = await image.read(limit + 1)
        await image.close()
        if not content:
            raise HTTPException(status_code=400, detail="上传图像为空")
        if len(content) > limit:
            raise HTTPException(status_code=413, detail="上传图像超过大小限制")

        try:
            record, created = service.create_task(content, task_id, strength)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except FileExistsError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

        if created:
            background_tasks.add_task(service.run_task, record["task_id"])
        return view(record)

    @app.get("/v1/enhancements/{task_id}", response_model=TaskView)
    def get_enhancement(task_id: str) -> TaskView:
        try:
            record = service.get_task(task_id)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="task_id 必须是 UUID") from exc
        if record is None:
            raise HTTPException(status_code=404, detail="任务不存在")
        return view(record)

    def artifact_response(task_id: str, key: str, media_type: str) -> FileResponse:
        try:
            path = service.artifact(task_id, key)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="task_id 必须是 UUID") from exc
        if path is None:
            raise HTTPException(status_code=404, detail="文件尚未生成或任务不存在")
        return FileResponse(path, media_type=media_type, filename=path.name)

    @app.get("/v1/enhancements/{task_id}/original")
    def get_original(task_id: str) -> FileResponse:
        return artifact_response(task_id, "original_file", "application/octet-stream")

    @app.get("/v1/enhancements/{task_id}/result")
    def get_result(task_id: str) -> FileResponse:
        return artifact_response(task_id, "result_file", "image/png")

    @app.get("/v1/enhancements/{task_id}/star-mask")
    def get_star_mask(task_id: str) -> FileResponse:
        return artifact_response(task_id, "mask_file", "image/png")

    return app


app = create_app()
