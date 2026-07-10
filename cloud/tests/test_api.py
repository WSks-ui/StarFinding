from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_create_query_and_download_local_task(tmp_path, synthetic_sky_bytes: bytes) -> None:
    app = create_app(Settings(data_dir=tmp_path, backend="local"))
    task_id = str(uuid4())
    with TestClient(app) as client:
        response = client.post(
            "/v1/enhancements",
            files={"image": ("sky.jpg", synthetic_sky_bytes, "image/jpeg")},
            data={"task_id": task_id, "strength": "0.7"},
        )
        assert response.status_code == 202

        detail = client.get(f"/v1/enhancements/{task_id}")
        assert detail.status_code == 200
        payload = detail.json()
        assert payload["state"] == "succeeded"
        assert payload["backend_used"] == "local"
        assert payload["input_sha256"]
        assert payload["output_sha256"]

        original = client.get(payload["links"]["original"])
        result = client.get(payload["links"]["result"])
        mask = client.get(payload["links"]["star_mask"])
        assert original.content == synthetic_sky_bytes
        assert result.headers["content-type"].startswith("image/png")
        assert mask.headers["content-type"].startswith("image/png")


def test_idempotency_rejects_different_image(tmp_path, synthetic_sky_bytes: bytes) -> None:
    app = create_app(Settings(data_dir=tmp_path, backend="mock"))
    task_id = str(uuid4())
    with TestClient(app) as client:
        first = client.post(
            "/v1/enhancements",
            files={"image": ("sky.jpg", synthetic_sky_bytes, "image/jpeg")},
            data={"task_id": task_id},
        )
        assert first.status_code == 202

        repeated = client.post(
            "/v1/enhancements",
            files={"image": ("sky.jpg", synthetic_sky_bytes, "image/jpeg")},
            data={"task_id": task_id},
        )
        assert repeated.status_code == 202

        conflict = client.post(
            "/v1/enhancements",
            files={"image": ("other.jpg", synthetic_sky_bytes + b"changed", "image/jpeg")},
            data={"task_id": task_id},
        )
        assert conflict.status_code == 409


def test_modelarts_failure_falls_back_to_local(tmp_path, synthetic_sky_bytes: bytes) -> None:
    settings = Settings(
        data_dir=tmp_path,
        backend="modelarts",
        modelarts_enabled=True,
        modelarts_endpoint="http://127.0.0.1:1/unavailable",
        modelarts_token="test-token",
        modelarts_timeout_seconds=0.2,
    )
    app = create_app(settings)
    with TestClient(app) as client:
        response = client.post(
            "/v1/enhancements",
            files={"image": ("sky.jpg", synthetic_sky_bytes, "image/jpeg")},
        )
        task_id = response.json()["task_id"]
        payload = client.get(f"/v1/enhancements/{task_id}").json()

    assert payload["state"] == "succeeded"
    assert payload["backend_used"] == "local_fallback"
    assert "ModelArts" in payload["fallback_reason"]


def test_health_never_returns_secrets(tmp_path) -> None:
    settings = Settings(
        data_dir=tmp_path,
        modelarts_enabled=True,
        modelarts_endpoint="https://example.invalid",
        modelarts_token="super-secret",
        obs_endpoint="https://obs.example.invalid",
        obs_access_key_id="ak-secret",
        obs_secret_access_key="sk-secret",
        obs_bucket="bucket",
    )
    client = TestClient(create_app(settings))
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["modelarts_configured"] is True
    assert response.json()["obs_configured"] is True
    assert "secret" not in response.text
