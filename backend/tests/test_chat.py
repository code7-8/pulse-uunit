import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from backend.main import create_app


@pytest.fixture
def chat_client(tmp_path):
    app = create_app(tmp_path / "chat.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads")
    with TestClient(app) as client:
        yield client


def account(client, number):
    response = client.post("/api/auth/register", json={"email": f"person{number}@example.com", "password": "StrongPassword123!", "name": f"Студент {number}"})
    assert response.status_code == 201
    result = response.json()
    return {"Authorization": "Bearer " + result["token"]}, result["user"]


def befriend(client, first_headers, first_user, second_headers, second_user):
    assert client.put(f"/api/users/{second_user['id']}/friend-request", headers=first_headers).status_code == 200
    assert client.post(f"/api/users/{first_user['id']}/friend-request/accept", headers=second_headers).status_code == 200


def chat(client, first_headers, second_user):
    response = client.post("/api/chats", headers=first_headers, json={"user_id": second_user["id"]})
    assert response.status_code == 200, response.text
    return response.json()


def photo_bytes():
    source = io.BytesIO()
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (80, 40), (80, 140, 170)).save(source, "JPEG", exif=exif)
    return source.getvalue()


def test_chat_requires_accepted_mutual_friendship_and_forbids_self(chat_client):
    client = chat_client
    alice, alice_user = account(client, 1)
    bob, bob_user = account(client, 2)
    assert client.post("/api/chats", json={"user_id": bob_user["id"]}).status_code == 401
    assert client.post("/api/chats", headers=alice, json={"user_id": alice_user["id"]}).status_code == 422
    assert client.post("/api/chats", headers=alice, json={"user_id": bob_user["id"]}).status_code == 403
    client.put(f"/api/users/{bob_user['id']}/friend-request", headers=alice)
    assert client.post("/api/chats", headers=alice, json={"user_id": bob_user["id"]}).status_code == 403
    client.post(f"/api/users/{alice_user['id']}/friend-request/accept", headers=bob)
    result = chat(client, alice, bob_user)
    assert result["peer"]["id"] == bob_user["id"] and result["can_send"]
    assert chat(client, bob, alice_user)["id"] == result["id"]
    assert client.get("/api/chats", headers=alice).json()["total"] == 1
    assert client.get("/api/chats", headers=bob).json()["total"] == 1


def test_chat_text_unread_read_privacy_and_pagination(chat_client):
    client = chat_client
    alice, alice_user = account(client, 1)
    bob, bob_user = account(client, 2)
    stranger, stranger_user = account(client, 3)
    befriend(client, alice, alice_user, bob, bob_user)
    chat_id = chat(client, alice, bob_user)["id"]
    ids = []
    for index in range(3):
        sent = client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"body": f"Сообщение {index}"})
        assert sent.status_code == 201
        ids.append(sent.json()["id"])
        assert sent.json()["sender_id"] == alice_user["id"]
    assert client.get("/api/chats", headers=alice).json()["items"][0]["unread_count"] == 0
    assert client.get("/api/chats", headers=bob).json()["items"][0]["unread_count"] == 3
    assert client.get("/api/chats", headers=stranger).json()["items"] == []
    assert client.get(f"/api/chats/{chat_id}/messages", headers=stranger).status_code == 404
    assert client.post(f"/api/chats/{chat_id}/messages", headers=stranger, json={"body": "Чужое сообщение"}).status_code == 404
    assert client.put(f"/api/chats/{chat_id}/read", headers=stranger).status_code == 404
    assert client.put(f"/api/chats/{chat_id}/read", headers=alice).status_code == 200
    assert client.get("/api/chats", headers=bob).json()["items"][0]["unread_count"] == 3
    assert client.put(f"/api/chats/{chat_id}/read", headers=bob).status_code == 200
    assert client.get("/api/chats", headers=bob).json()["items"][0]["unread_count"] == 0
    full = client.get(f"/api/chats/{chat_id}/messages", headers=bob).json()
    assert [item["id"] for item in full["items"]] == ids
    assert all(item["read_at"] for item in full["items"])
    assert full["has_more"] is False
    recent = client.get(f"/api/chats/{chat_id}/messages?page_size=2", headers=bob).json()
    assert [item["id"] for item in recent["items"]] == ids[1:] and recent["has_more"]
    oldest = client.get(f"/api/chats/{chat_id}/messages?before_id={ids[1]}&page_size=2", headers=bob).json()
    assert [item["id"] for item in oldest["items"]] == ids[:1] and not oldest["has_more"]
    new = client.get(f"/api/chats/{chat_id}/messages?after_id={ids[1]}&page_size=2", headers=bob).json()
    assert [item["id"] for item in new["items"]] == ids[2:] and not new["has_more"]
    empty = client.get(f"/api/chats/{chat_id}/messages?after_id={ids[-1]}", headers=bob).json()
    assert empty["items"] == [] and not empty["has_more"]
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"body": "  "}).status_code == 422
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"body": "x" * 4001}).status_code == 422


def test_chat_photo_is_private_oriented_and_scoped_to_conversation(chat_client):
    client = chat_client
    alice, alice_user = account(client, 1)
    bob, bob_user = account(client, 2)
    carol, carol_user = account(client, 3)
    befriend(client, alice, alice_user, bob, bob_user)
    befriend(client, alice, alice_user, carol, carol_user)
    chat_id = chat(client, alice, bob_user)["id"]
    other_chat_id = chat(client, alice, carol_user)["id"]
    uploaded = client.post(f"/api/chats/{chat_id}/images", headers=alice, files={"file": ("phone.jpg", photo_bytes(), "image/jpeg")})
    assert uploaded.status_code == 201, uploaded.text
    url = uploaded.json()["url"]
    assert url.startswith(f"/api/chats/{chat_id}/images/")
    assert client.get(url).status_code == 401
    assert client.get(url, headers=carol).status_code == 404
    private = client.get(url, headers=bob)
    assert private.status_code == 200 and private.headers["Cache-Control"] == "private, no-store"
    image = Image.open(io.BytesIO(private.content))
    assert image.size == (40, 80) and not image.getexif()
    sent = client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"image_url": url})
    assert sent.status_code == 201 and sent.json()["image_url"] == url
    assert sent.json()["body"] == ""
    assert client.post(f"/api/chats/{other_chat_id}/messages", headers=alice, json={"image_url": url}).status_code == 422
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"image_url": "/uploads/public.jpg"}).status_code == 422
    fabricated = f"/api/chats/{chat_id}/images/" + "a" * 40 + ".jpg"
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"image_url": fabricated}).status_code == 422
    assert client.post(f"/api/chats/{chat_id}/images", headers=carol, files={"file": ("phone.jpg", photo_bytes(), "image/jpeg")}).status_code == 404
    assert client.post(f"/api/chats/{chat_id}/images", headers=alice, files={"file": ("bad.jpg", b"not an image", "image/jpeg")}).status_code == 422
    assert client.get(f"/api/chats/{chat_id}/images/nope.jpg", headers=bob).status_code == 404
    # The same basename is never available through the public post upload mount.
    assert client.get("/uploads/" + url.rsplit("/", 1)[-1]).status_code == 404


def test_unfriending_preserves_chat_history_but_disables_text_and_photos(chat_client):
    client = chat_client
    alice, alice_user = account(client, 1)
    bob, bob_user = account(client, 2)
    befriend(client, alice, alice_user, bob, bob_user)
    chat_id = chat(client, alice, bob_user)["id"]
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"body": "История до удаления дружбы"}).status_code == 201
    uploaded = client.post(f"/api/chats/{chat_id}/images", headers=alice, files={"file": ("phone.jpg", photo_bytes(), "image/jpeg")}).json()
    client.delete(f"/api/users/{bob_user['id']}/friendship", headers=alice)
    assert chat(client, alice, bob_user)["can_send"] is False
    history = client.get(f"/api/chats/{chat_id}/messages", headers=bob)
    assert history.status_code == 200 and history.json()["total"] == 1
    assert client.get(uploaded["url"], headers=bob).status_code == 200
    assert client.post(f"/api/chats/{chat_id}/messages", headers=alice, json={"body": "Новое сообщение"}).status_code == 403
    assert client.post(f"/api/chats/{chat_id}/messages", headers=bob, json={"body": "Ответ"}).status_code == 403
    assert client.post(f"/api/chats/{chat_id}/images", headers=alice, files={"file": ("phone.jpg", photo_bytes(), "image/jpeg")}).status_code == 403
