import io
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from backend.deployment import PublicSettings, client_address
from backend.main import create_app
from backend.storage import ImageStorage


@pytest.fixture
def public_client(tmp_path):
    app = create_app(tmp_path / "public.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads",
                     public_settings=PublicSettings(enabled=True))
    with TestClient(app) as client:
        yield client


def test_public_routes_hide_docs_source_database_and_secrets(public_client):
    assert public_client.get("/api/health").json()["public"] is True
    for path in ("/docs", "/redoc", "/openapi.json", "/backend/main.py", "/runtime/server/ДОСТУПЫ.txt", "/.env", "/media/../data/pulse.sqlite3"):
        assert public_client.get(path).status_code == 404
    response = public_client.get("/api/categories")
    assert response.status_code == 200
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["cache-control"] == "no-store"
    assert public_client.get("/api/me").status_code == 401
    assert public_client.get("/api/moderation/posts").status_code == 401


def test_public_rejects_oversized_declared_and_chunked_json(public_client):
    assert public_client.post("/api/auth/register", content=b"{}", headers={"Content-Length": "9000000"}).status_code == 413
    assert public_client.post("/api/auth/register", content=iter([b"x" * 40000, b"y" * 40000])).status_code == 413
    assert public_client.get("/api/posts?search=" + "a" * 5000).status_code == 414
    assert public_client.get("/api/health").status_code == 200


def test_public_body_limit_allows_real_photo_upload(public_client):
    auth = public_client.post("/api/auth/register", json={"email": "photo@example.com", "password": "SomePassword123!", "name": "Автор Фото"})
    assert auth.status_code == 201
    headers = {"Authorization": "Bearer " + auth.json()["token"]}
    data = io.BytesIO()
    Image.new("RGB", (20, 30), "red").save(data, "PNG")
    uploaded = public_client.post("/api/uploads", headers=headers, files={"file": ("photo.png", data.getvalue(), "image/png")})
    assert uploaded.status_code == 201, uploaded.text
    assert public_client.get(uploaded.json()["url"]).status_code == 200


def test_public_refuses_default_demo_credentials(tmp_path):
    app = create_app(tmp_path / "unsafe.sqlite3", seed_demo=True, upload_dir=tmp_path / "uploads",
                     public_settings=PublicSettings(enabled=True))
    with pytest.raises(RuntimeError, match="shared demo passwords"):
        with TestClient(app):
            pass


def test_public_rate_limits_separate_clients(tmp_path):
    settings = PublicSettings(enabled=True, proxy="cloudflare", requests_per_minute=2)
    app = create_app(tmp_path / "limited.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads", public_settings=settings)
    with TestClient(app, client=("127.0.0.1", 51000)) as client:
        first, second = {"CF-Connecting-IP": "198.51.100.1"}, {"CF-Connecting-IP": "198.51.100.2"}
        assert client.get("/api/health", headers=first).status_code == 200
        assert client.get("/api/health", headers=first).status_code == 200
        limited = client.get("/api/health", headers=first)
        assert limited.status_code == 429 and limited.headers["retry-after"] == "60"
        assert client.get("/api/health", headers=second).status_code == 200


def test_proxy_headers_are_not_trusted_from_remote_peers():
    scope = {"client": ("198.51.100.20", 1234), "headers": [(b"cf-connecting-ip", b"198.51.100.99")]}
    assert client_address(scope, "cloudflare") == "198.51.100.20"
    scope["client"] = ("127.0.0.1", 1234)
    assert client_address(scope, "cloudflare") == "198.51.100.99"
    assert client_address(scope, "none") == "127.0.0.1"
    scope["headers"] = [(b"cf-connecting-ip", b"bad address")]
    assert client_address(scope, "cloudflare") == "127.0.0.1"


def test_shared_storage_quota_covers_chat_and_public_images(tmp_path):
    covers, chat = tmp_path / "uploads", tmp_path / "chat_uploads"
    storage = ImageStorage([covers, chat], quota_bytes=1000, minimum_free_bytes=0)
    data = io.BytesIO()
    Image.new("RGB", (30, 30), "blue").save(data, "PNG")
    first = storage.save(data.getvalue(), covers)
    assert (covers / first).is_file()
    storage.quota_bytes = (covers / first).stat().st_size + 1
    with pytest.raises(HTTPException) as error:
        storage.save(data.getvalue(), chat / "1")
    assert error.value.status_code == 507
    assert not list(chat.rglob("*.jpg"))
    with pytest.raises(ValueError, match="outside"):
        storage.save(data.getvalue(), tmp_path / "other")


def test_storage_rejects_disguised_executable(tmp_path):
    storage = ImageStorage([tmp_path / "uploads"], minimum_free_bytes=0)
    with pytest.raises(HTTPException) as error:
        storage.save(b"MZ" + b"not-an-image" * 20, tmp_path / "uploads")
    assert error.value.status_code == 422
