from __future__ import annotations

from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

from conftest import wait_for_task


def test_health_camera_and_liveview(client: TestClient) -> None:
    health = client.get("/health")
    assert health.status_code == 200
    payload = health.json()
    assert payload["status"] == "ok"
    assert payload["camera"]["backend"] == "mock"
    assert payload["camera"]["simulated"] is True
    assert payload["plate_solver"]["simulated"] is True
    assert payload["ffmpeg"]["available"] is False

    capabilities = client.get("/api/v1/camera/capabilities").json()
    assert capabilities["raw_jpeg"] is True
    assert capabilities["max_exposure_seconds"] == 300

    preview = client.get("/api/v1/camera/liveview")
    assert preview.status_code == 200
    assert preview.headers["content-type"].startswith("image/jpeg")
    assert preview.content[:2] == b"\xff\xd8"


def test_capture_is_idempotent_and_files_are_downloadable(client: TestClient) -> None:
    request = {
        "iso": "800",
        "aperture": "4",
        "exposure_seconds": 10,
        "count": 2,
        "interval_seconds": 0,
        "raw_jpeg": True,
        "label": "orion",
    }
    first = client.post("/api/v1/capture/tasks", json=request, headers={"Idempotency-Key": "capture-night-001"})
    second = client.post("/api/v1/capture/tasks", json=request, headers={"Idempotency-Key": "capture-night-001"})
    assert first.status_code == second.status_code == 202
    assert first.json()["id"] == second.json()["id"]

    task = wait_for_task(client, first.json()["id"])
    assert task["status"] == "succeeded", task
    assert task["output"]["captured_frames"] == 2
    assert task["output"]["simulated"] is True
    files = task["output"]["files"]
    assert len(files) == 4
    jpeg = next(record for record in files if record["mime_type"] == "image/jpeg")
    download = client.get(f"/api/v1/files/{jpeg['id']}")
    assert download.status_code == 200
    assert download.content[:2] == b"\xff\xd8"

    with client.websocket_connect(f"/ws/tasks/{task['id']}") as websocket:
        event = websocket.receive_json()
        assert event["status"] == "succeeded"


def test_plate_solve_and_stack_pipeline(client: TestClient) -> None:
    capture = client.post(
        "/api/v1/capture/tasks",
        json={"count": 3, "raw_jpeg": False, "exposure_seconds": 5, "label": "stack"},
    )
    capture_task = wait_for_task(client, capture.json()["id"])
    assert capture_task["status"] == "succeeded"
    file_ids = [record["id"] for record in capture_task["output"]["files"]]

    plate = client.post(
        "/api/v1/plate-solve",
        json={"file_id": file_ids[0], "hint_ra_deg": 12.5, "hint_dec_deg": -8.25},
    )
    plate_task = wait_for_task(client, plate.json()["id"])
    assert plate_task["status"] == "succeeded", plate_task
    result = plate_task["output"]["plate_solve"]
    assert result["simulated"] is True
    assert result["ra_deg"] == 12.5
    assert result["dec_deg"] == -8.25

    stack = client.post(
        "/api/v1/stack",
        json={"file_ids": file_ids, "reject_bad_frames": True, "correct_light_pollution": True},
    )
    stack_task = wait_for_task(client, stack.json()["id"], timeout=25)
    assert stack_task["status"] == "succeeded", stack_task
    assert stack_task["output"]["accepted_count"] >= 2
    result_file = stack_task["output"]["file"]
    image = client.get(f"/api/v1/files/{result_file['id']}")
    assert image.status_code == 200
    assert image.content[:2] == b"\xff\xd8"


def test_upload_validation_and_task_errors(client: TestClient) -> None:
    buffer = BytesIO()
    Image.new("RGB", (64, 48), (10, 20, 30)).save(buffer, "PNG")
    upload = client.post("/api/v1/files", files={"file": ("sample.png", buffer.getvalue(), "image/png")})
    assert upload.status_code == 201
    record = upload.json()
    assert record["kind"] == "upload"
    assert client.get(f"/api/v1/files/{record['id']}").status_code == 200

    invalid = client.post("/api/v1/files", files={"file": ("sample.txt", b"not image", "text/plain")})
    assert invalid.status_code == 415
    assert client.get("/api/v1/tasks/not-a-task").status_code == 404
    odd_video = client.post(
        "/api/v1/timelapse",
        json={"file_ids": ["a", "b"], "width": 1921, "height": 1080},
    )
    assert odd_video.status_code == 422


def test_idempotency_key_cannot_cross_task_types(client: TestClient) -> None:
    capture = client.post(
        "/api/v1/capture/tasks",
        json={"count": 1, "raw_jpeg": False, "label": "once"},
        headers={"Idempotency-Key": "same-key"},
    )
    assert capture.status_code == 202
    conflict = client.post(
        "/api/v1/plate-solve",
        json={"file_id": "missing"},
        headers={"Idempotency-Key": "same-key"},
    )
    assert conflict.status_code == 409
