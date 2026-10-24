"""Real HTTPS smoke test. Temporary users, posts and images are removed afterward."""
import io
import json
from pathlib import Path
import re
import secrets
import shutil
import sqlite3
import sys
from datetime import datetime

import httpx
from PIL import Image

WORKSPACE = Path(__file__).resolve().parents[1]
ROOT = WORKSPACE / "runtime" / "server"
state = json.loads((ROOT / "status.json").read_text(encoding="utf-8"))
base = state["url"]
checks, users, posts, chats, covers = [], [], [], [], []
marker = secrets.token_hex(6)


def call(client, method, path, expected=200, **kwargs):
    response = client.request(method, "/api" + path, **kwargs)
    if response.status_code != expected:
        raise RuntimeError(f"{method} {path}: HTTP {response.status_code}, expected {expected}")
    return response.json()


def signup(client, suffix):
    data = call(client, "POST", "/auth/register", expected=201,
        json={"email": f"smoke-{marker}-{suffix}@example.com", "password": secrets.token_urlsafe(18), "name": "Проверка сервера"})
    users.append(data["user"]["id"])
    client.headers["Authorization"] = "Bearer " + data["token"]
    return data["user"]


try:
    with httpx.Client(base_url=base, timeout=35, trust_env=False, limits=httpx.Limits(keepalive_expiry=2)) as author, httpx.Client(base_url=base, timeout=35, trust_env=False, limits=httpx.Limits(keepalive_expiry=2)) as mod, httpx.Client(base_url=base, timeout=35, trust_env=False, limits=httpx.Limits(keepalive_expiry=2)) as guest:
        assert call(guest, "GET", "/health")["public"] is True
        assert call(guest, "GET", "/posts")["total"] >= 1
        checks.append("HTTPS, health and public feed")
        person = signup(author, "author")
        assert call(author, "GET", "/friends")["total"] == 2
        assert len(call(author, "GET", "/friends/requests")["incoming"]) == 1
        preview_chats = call(author, "GET", "/chats")["items"]
        assert len(preview_chats) == 2 and all(chat["can_send"] for chat in preview_chats)
        checks.append("New reviewer has demo friends, an incoming request and two usable chats")
        credentials = (ROOT / "ДОСТУПЫ.txt").read_text(encoding="utf-8")
        password = re.search(r"moderator@pulse\.local\nРоль: moderator\nПароль: ([^\n]+)", credentials).group(1)
        session = call(mod, "POST", "/auth/login", json={"email": "moderator@pulse.local", "password": password})
        mod.headers["Authorization"] = "Bearer " + session["token"]
        moderator_id = session["user"]["id"]
        picture = io.BytesIO()
        Image.new("RGB", (24, 32), "purple").save(picture, "PNG")
        cover = call(author, "POST", "/uploads", expected=201, files={"file": ("test.png", picture.getvalue(), "image/png")})["url"]
        covers.append(cover)
        title = "Проверка общего сервера " + marker
        post = call(author, "POST", "/posts", expected=201, json={"type": "news", "title": title,
            "body": "Проверяем публикацию и обязательную проверку редактором через внешний HTTPS-адрес.",
            "category": "community", "cover_url": cover})
        posts.append(post["id"])
        call(guest, "GET", f"/posts/{post['id']}", expected=404)
        returned = call(mod, "POST", f"/moderation/posts/{post['id']}/decision", json={"decision": "changes_requested",
            "expected_updated_at": post["updated_at"], "reason": "Уточните место проведения встречи"})
        assert returned["status"] == "changes_requested"
        revised = call(author, "PATCH", f"/posts/{post['id']}", json={"body": "Встреча пройдёт в студенческом коворкинге. Приглашаем всех участников сообщества."})
        pending = call(author, "POST", f"/posts/{post['id']}/submit")
        reviewed = call(mod, "GET", f"/posts/{post['id']}")
        call(mod, "POST", f"/moderation/posts/{post['id']}/decision", json={"decision": "publish", "expected_updated_at": reviewed["updated_at"]})
        assert call(guest, "GET", f"/posts/{post['id']}")["status"] == "published"
        call(author, "PUT", f"/posts/{post['id']}/reaction", json={"reaction": "heart"})
        call(author, "POST", f"/posts/{post['id']}/comments", expected=201, json={"body": "Комментарии через внешний сервер работают"})
        checks.append("Author, private pending post, return, revision, approval, reactions and comments")
        call(author, "PUT", f"/users/{moderator_id}/friend-request")
        call(mod, "POST", f"/users/{person['id']}/friend-request/accept")
        chat = call(author, "POST", "/chats", json={"user_id": moderator_id})
        chats.append(chat["id"])
        image = call(author, "POST", f"/chats/{chat['id']}/images", expected=201,
            files={"file": ("private.png", picture.getvalue(), "image/png")})["url"]
        message = call(author, "POST", f"/chats/{chat['id']}/messages", expected=201,
            json={"body": "Проверка фотографии", "image_url": image})
        messages = call(mod, "GET", f"/chats/{chat['id']}/messages")["items"]
        assert any(m["id"] == message["id"] for m in messages)
        assert mod.get(image).status_code == 200
        assert guest.get(image).status_code == 401
        signup(guest, "outsider")
        assert guest.get(image).status_code == 404
        call(mod, "PUT", f"/chats/{chat['id']}/read")
        checks.append("Friendship, chat delivery, private photo isolation and read receipts")
        for path in ("/docs", "/runtime/server/ДОСТУПЫ.txt", "/backend/main.py"):
            assert guest.get(path).status_code == 404
        checks.append("Source, credentials and API documentation are not public")
finally:
    with sqlite3.connect(ROOT / "data" / "pulse.sqlite3") as connection:
        connection.execute("PRAGMA foreign_keys=ON")
        for user_id in users:
            chats.extend(row[0] for row in connection.execute("SELECT id FROM conversations WHERE user_low=? OR user_high=?", (user_id, user_id)) if row[0] not in chats)
        for post_id in posts:
            connection.execute("DELETE FROM notifications WHERE post_id=?", (post_id,))
            connection.execute("DELETE FROM posts WHERE id=?", (post_id,))
        for chat_id in chats:
            connection.execute("DELETE FROM conversations WHERE id=?", (chat_id,))
        for user_id in users:
            connection.execute("DELETE FROM users WHERE id=? AND email LIKE ?", (user_id, f"smoke-{marker}-%@example.com"))
    for chat_id in chats:
        folder = ROOT / "data" / "chat_uploads" / str(int(chat_id))
        if folder.exists() and folder.resolve().parent == (ROOT / "data" / "chat_uploads").resolve():
            shutil.rmtree(folder)
    for cover in covers:
        name = cover.rsplit("/", 1)[-1]
        if re.fullmatch(r"[a-f0-9]{40}\.jpg", name):
            (ROOT / "data" / "uploads" / name).unlink(missing_ok=True)

report = {"url": base, "checked_at": datetime.now().astimezone().isoformat(), "passed": checks}
(ROOT / "https-check.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
