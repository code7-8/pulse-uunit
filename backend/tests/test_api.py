import io
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from backend.database import connect
from backend.main import create_app


@pytest.fixture
def client(tmp_path):
    app = create_app(tmp_path / "test.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads")
    with TestClient(app) as test_client:
        yield test_client


def register(client, email="author@example.com", name="Автор Публикации"):
    response = client.post("/api/auth/register", json={"email": email, "password": "TestPassword123!", "name": name, "faculty": "ИИМР", "course": 2})
    assert response.status_code == 201, response.text
    result = response.json()
    return {"Authorization": f"Bearer {result['token']}"}, result["user"]


def moderator(client):
    headers, user = register(client, "moderator@example.com", "Модератор Редакции")
    with connect(client.app.state.db_path) as connection:
        connection.execute("UPDATE users SET role='moderator' WHERE id=?", (user["id"],))
    return headers, user


def make_post(client, headers, **changes):
    payload = {"type": "news", "title": "Студенческая встреча в кампусе", "body": "Приглашаем студентов на встречу сообщества. Обсудим проекты и познакомимся.", "category": "community", "submit": True}
    payload.update(changes)
    response = client.post("/api/posts", headers=headers, json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def publish(client, moderator_headers, post_id):
    revision = client.get(f"/api/posts/{post_id}", headers=moderator_headers).json()["updated_at"]
    response = client.post(f"/api/moderation/posts/{post_id}/decision", headers=moderator_headers, json={"decision": "publish", "expected_updated_at": revision})
    assert response.status_code == 200, response.text
    return response.json()


def test_auth_register_login_logout_and_session_storage(client):
    headers, user = register(client)
    assert user["email"] == "author@example.com"
    assert client.get("/api/me", headers=headers).json()["id"] == user["id"]
    assert client.get("/api/me").status_code == 401
    assert client.post("/api/auth/login", json={"email": "author@example.com", "password": "wrong"}).status_code == 401
    response = client.post("/api/auth/login", json={"email": "AUTHOR@example.com", "password": "TestPassword123!"})
    assert response.status_code == 200
    with connect(client.app.state.db_path) as connection:
        stored = connection.execute("SELECT password_hash FROM users").fetchone()[0]
        assert "TestPassword123!" not in stored
        assert headers["Authorization"][7:] not in [row[0] for row in connection.execute("SELECT token_hash FROM sessions")]
    assert client.post("/api/auth/logout", headers=headers).status_code == 200
    assert client.get("/api/me", headers=headers).status_code == 401


def test_validation_email_duplicate_and_role_escalation(client):
    headers, user = register(client)
    duplicate = client.post("/api/auth/register", json={"email": "AUTHOR@example.com", "password": "TestPassword123!", "name": "Автор Публикации"})
    assert duplicate.status_code == 409
    assert client.patch("/api/me", headers=headers, json={"role": "moderator"}).status_code == 422
    assert client.patch("/api/me", headers=headers, json={"name": None}).status_code == 422
    assert client.get("/api/moderation/posts", headers=headers).status_code == 403
    assert client.post("/api/posts", headers=headers, json={"title": "123"}).json()["detail"]
    public = client.get(f"/api/users/{user['id']}").json()
    assert public["email"] == ""


def test_profile_edit_handle_color_and_uniqueness(client):
    headers, user = register(client)
    other_headers, other = register(client, "other@example.com", "Другой Студент")
    response = client.patch("/api/me", headers=headers, json={"name": "Новое Имя", "bio": "Занимаюсь студенческими проектами.", "handle": "Alex.New_2", "avatar_color": "#aabbcc", "course": None})
    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["name"] == "Новое Имя"
    assert updated["bio"] == "Занимаюсь студенческими проектами."
    assert updated["handle"] == "alex.new_2" and updated["avatar_color"] == "#AABBCC"
    assert updated["course"] is None
    # Keeping your own handle is valid; another user cannot claim it in another case.
    assert client.patch("/api/me", headers=headers, json={"handle": "ALEX.NEW_2"}).status_code == 200
    assert client.patch("/api/me", headers=other_headers, json={"handle": "ALEX.NEW_2"}).status_code == 409
    for invalid in ("ab", "имя", "with space", "<script>", "x" * 31):
        assert client.patch("/api/me", headers=headers, json={"handle": invalid}).status_code == 422
    for invalid in ("red", "#abc", "#zzzzzz", "#1234567"):
        assert client.patch("/api/me", headers=headers, json={"avatar_color": invalid}).status_code == 422
    for field in ("name", "handle", "avatar_color"):
        assert client.patch("/api/me", headers=headers, json={field: None}).status_code == 422
    assert client.patch("/api/me", headers=headers, json={"role": "moderator"}).status_code == 422


def test_premoderation_revision_permissions_and_history(client):
    author_headers, author = register(client)
    other_headers, other = register(client, "other@example.com")
    mod_headers, mod = moderator(client)
    post = make_post(client, author_headers)
    post_id = post["id"]
    assert post["status"] == "pending"
    assert client.get("/api/posts").json()["total"] == 0
    assert client.get(f"/api/posts/{post_id}").status_code == 404
    assert client.get(f"/api/posts/{post_id}", headers=other_headers).status_code == 404
    assert client.get(f"/api/posts/{post_id}", headers=author_headers).status_code == 200
    assert client.get("/api/me/posts", headers=author_headers).json()["total"] == 1
    assert client.get(f"/api/users/{author['id']}/posts").json()["total"] == 0
    assert client.post(f"/api/moderation/posts/{post_id}/decision", headers=author_headers, json={"decision": "publish", "expected_updated_at": post["updated_at"]}).status_code == 403
    assert client.patch(f"/api/posts/{post_id}", headers=mod_headers, json={"title": "Чужое изменение"}).status_code == 403
    response = client.post(f"/api/moderation/posts/{post_id}/decision", headers=mod_headers, json={"decision": "changes_requested", "expected_updated_at": post["updated_at"]})
    assert response.status_code == 422
    response = client.post(f"/api/moderation/posts/{post_id}/decision", headers=mod_headers, json={"decision": "changes_requested", "reason": "Добавьте место встречи", "expected_updated_at": post["updated_at"]})
    assert response.json()["moderation_reason"] == "Добавьте место встречи"
    assert client.post(f"/api/posts/{post_id}/submit", headers=author_headers).json()["status"] == "pending"
    published = publish(client, mod_headers, post_id)
    assert published["published_at"]
    assert client.get("/api/posts").json()["total"] == 1
    assert client.post(f"/api/moderation/posts/{post_id}/decision", headers=mod_headers, json={"decision": "reject", "reason": "Повторная проверка", "expected_updated_at": published["updated_at"]}).status_code == 409
    edited = client.patch(f"/api/posts/{post_id}", headers=author_headers, json={"body": "Полностью изменённый текст публикации, который ещё не прошёл проверку модератором."})
    assert edited.json()["status"] == "pending"
    assert edited.json()["published_at"] is None
    assert client.get(f"/api/posts/{post_id}").status_code == 404
    assert client.get("/api/posts").json()["total"] == 0
    history = client.get(f"/api/moderation/posts/{post_id}/history", headers=author_headers).json()["items"]
    assert [entry["decision"] for entry in history] == ["submitted", "changes_requested", "submitted", "publish", "edited"]
    assert client.get(f"/api/moderation/posts/{post_id}/history", headers=other_headers).status_code in (403, 404)


def test_moderator_cannot_approve_own_work(client):
    headers, _ = moderator(client)
    post = make_post(client, headers)
    assert client.post(f"/api/moderation/posts/{post['id']}/decision", headers=headers, json={"decision": "publish", "expected_updated_at": post["updated_at"]}).status_code == 403


def test_stale_moderation_cannot_publish_new_unreviewed_text(client):
    author_headers, _ = register(client)
    mod_headers, _ = moderator(client)
    post = make_post(client, author_headers)
    previous_revision = post["updated_at"]
    edited = client.patch(f"/api/posts/{post['id']}", headers=author_headers, json={"body": "Новый текст публикации после того, как модератор открыл предыдущую версию для проверки."}).json()
    assert edited["updated_at"] != previous_revision
    response = client.post(f"/api/moderation/posts/{post['id']}/decision", headers=mod_headers, json={"decision": "publish", "expected_updated_at": previous_revision})
    assert response.status_code == 409
    assert client.get(f"/api/posts/{post['id']}").status_code == 404
    publish(client, mod_headers, post["id"])


def test_friends_require_acceptance_and_recommendations_protect_privacy(client):
    viewer_headers, viewer = register(client, "viewer@example.com")
    friend_headers, friend = register(client, "friend@example.com", "Друг Студента")
    another_headers, another = register(client, "another@example.com", "Второй Друг")
    stranger_headers, stranger = register(client, "stranger@example.com", "Незнакомый Студент")
    mod_headers, _ = moderator(client)
    start = datetime.now(timezone.utc) + timedelta(hours=2)
    event = make_post(client, friend_headers, type="event", event_start=start.isoformat(), location="Коворкинг")
    publish(client, mod_headers, event["id"])
    client.put(f"/api/posts/{event['id']}/attendance", headers=friend_headers)
    client.put(f"/api/posts/{event['id']}/attendance", headers=stranger_headers)
    assert client.get("/api/posts?feed=friends").status_code == 401
    assert client.get("/api/posts?feed=friends", headers=viewer_headers).json()["total"] == 0
    assert client.get(f"/api/posts/{event['id']}", headers=viewer_headers).json()["friend_attendees"] == []
    assert client.put(f"/api/users/{viewer['id']}/friend-request", headers=viewer_headers).status_code == 422
    for _ in range(2):
        outgoing = client.put(f"/api/users/{friend['id']}/friend-request", headers=viewer_headers).json()
        assert outgoing["friendship_status"] == "outgoing"
    assert client.get("/api/friends", headers=viewer_headers).json()["total"] == 0
    assert client.get("/api/me", headers=viewer_headers).json()["friends_count"] == 0
    assert client.get("/api/posts?feed=friends", headers=viewer_headers).json()["total"] == 0
    assert client.post(f"/api/users/{friend['id']}/friend-request/accept", headers=viewer_headers).status_code == 409
    incoming = client.get("/api/friends/requests", headers=friend_headers).json()
    assert [item["id"] for item in incoming["incoming"]] == [viewer["id"]]
    accepted = client.post(f"/api/users/{viewer['id']}/friend-request/accept", headers=friend_headers).json()
    assert accepted["friendship_status"] == "friends" and accepted["friends_count"] == 1
    assert client.get("/api/friends", headers=viewer_headers).json()["total"] == 1
    feed = client.get("/api/posts?feed=friends", headers=viewer_headers).json()
    assert feed["total"] == 1
    assert feed["items"][0]["friends_attending_count"] == 1
    assert [person["id"] for person in feed["items"][0]["friend_attendees"]] == [friend["id"]]
    assert feed["items"][0]["attendees_count"] == 2
    # A second accepted friend increases rank; a past event never becomes a recommendation.
    client.put(f"/api/users/{another['id']}/friend-request", headers=viewer_headers)
    client.post(f"/api/users/{viewer['id']}/friend-request/accept", headers=another_headers)
    later = make_post(client, friend_headers, title="Вторая встреча сообщества", type="event", event_start=(start + timedelta(hours=1)).isoformat(), location="Библиотека")
    publish(client, mod_headers, later["id"])
    client.put(f"/api/posts/{later['id']}/attendance", headers=friend_headers)
    client.put(f"/api/posts/{later['id']}/attendance", headers=another_headers)
    past = make_post(client, friend_headers, title="Прошедшая встреча сообщества", type="event", event_start=(start - timedelta(days=2)).isoformat(), location="Библиотека")
    publish(client, mod_headers, past["id"])
    client.put(f"/api/posts/{past['id']}/attendance", headers=friend_headers)
    feed = client.get("/api/posts?feed=friends", headers=viewer_headers).json()
    assert [post["id"] for post in feed["items"]] == [later["id"], event["id"]]
    client.delete(f"/api/users/{friend['id']}/friendship", headers=viewer_headers)
    assert client.get("/api/me", headers=viewer_headers).json()["friends_count"] == 1
    remaining = client.get("/api/posts?feed=friends", headers=viewer_headers).json()
    assert [post["id"] for post in remaining["items"]] == [later["id"]]
    assert [person["id"] for person in remaining["items"][0]["friend_attendees"]] == [another["id"]]
    client.delete(f"/api/users/{another['id']}/friendship", headers=viewer_headers)
    assert client.get("/api/posts?feed=friends", headers=viewer_headers).json()["total"] == 0


def test_draft_edit_and_submit(client):
    headers, _ = register(client)
    draft = make_post(client, headers, submit=False)
    assert draft["status"] == "draft"
    assert client.patch(f"/api/posts/{draft['id']}", headers=headers, json={"title": "Обновлённый заголовок"}).json()["status"] == "draft"
    assert client.post(f"/api/posts/{draft['id']}/submit", headers=headers).json()["status"] == "pending"
    assert client.post(f"/api/posts/{draft['id']}/submit", headers=headers).status_code == 409


def test_follow_bookmark_reaction_and_attendance_are_idempotent(client):
    headers, author = register(client)
    visitor_headers, visitor = register(client, "visitor@example.com")
    mod_headers, _ = moderator(client)
    start = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    post = make_post(client, headers, type="event", event_start=start, location="Коворкинг", price="Бесплатно")
    publish(client, mod_headers, post["id"])
    for _ in range(2):
        followed = client.put(f"/api/users/{author['id']}/follow", headers=visitor_headers).json()
        assert followed["followers_count"] == 1
        assert followed["is_following"]
        bookmarked = client.put(f"/api/posts/{post['id']}/bookmark", headers=visitor_headers).json()
        assert bookmarked["is_bookmarked"]
        attending = client.put(f"/api/posts/{post['id']}/attendance", headers=visitor_headers).json()
        assert attending["attendees_count"] == 1
        reaction = client.put(f"/api/posts/{post['id']}/reaction", headers=visitor_headers, json={"reaction": "fire"}).json()
        assert reaction["reactions"]["fire"] == 1
    reaction = client.put(f"/api/posts/{post['id']}/reaction", headers=visitor_headers, json={"reaction": "heart"}).json()
    assert reaction["reactions"]["fire"] == 0 and reaction["reactions"]["heart"] == 1
    assert client.get("/api/posts?feed=following", headers=visitor_headers).json()["total"] == 1
    assert client.get("/api/posts?saved=true", headers=visitor_headers).json()["total"] == 1
    assert client.get("/api/posts?saved=true").status_code == 401
    assert client.put(f"/api/users/{visitor['id']}/follow", headers=visitor_headers).status_code == 422
    assert client.delete(f"/api/posts/{post['id']}/reaction", headers=visitor_headers).json()["my_reaction"] is None
    assert client.delete(f"/api/posts/{post['id']}/attendance", headers=visitor_headers).json()["attendees_count"] == 0
    assert not client.delete(f"/api/posts/{post['id']}/bookmark", headers=visitor_headers).json()["is_bookmarked"]
    assert not client.delete(f"/api/users/{author['id']}/follow", headers=visitor_headers).json()["is_following"]


def test_comments_reply_scope_reports_and_moderation(client):
    headers, _ = register(client)
    visitor_headers, _ = register(client, "visitor@example.com")
    mod_headers, _ = moderator(client)
    post = make_post(client, headers)
    other_post = make_post(client, headers, title="Другая студенческая встреча")
    publish(client, mod_headers, post["id"])
    publish(client, mod_headers, other_post["id"])
    assert client.post(f"/api/posts/{post['id']}/comments", json={"body": "Можно прийти?"}).status_code == 401
    comment = client.post(f"/api/posts/{post['id']}/comments", headers=visitor_headers, json={"body": "Можно прийти без ноутбука?"}).json()
    reply = client.post(f"/api/posts/{post['id']}/comments", headers=headers, json={"body": "Да, можно работать в паре.", "parent_id": comment["id"]})
    assert reply.status_code == 201
    assert client.post(f"/api/posts/{other_post['id']}/comments", headers=headers, json={"body": "Ответ в другом обсуждении", "parent_id": comment["id"]}).status_code == 422
    assert client.delete(f"/api/comments/{comment['id']}", headers=headers).status_code == 403
    assert client.post(f"/api/comments/{comment['id']}/report", headers=headers, json={"reason": "Проверьте комментарий"}).status_code == 201
    reports = client.get("/api/moderation/reports", headers=mod_headers).json()
    assert reports["total"] == 1
    assert reports["items"][0]["comment"]["id"] == comment["id"]
    assert client.get("/api/moderation/reports", headers=headers).status_code == 403
    report_id = reports["items"][0]["id"]
    assert client.post(f"/api/moderation/reports/{report_id}/resolve", headers=mod_headers).status_code == 200
    assert client.get("/api/moderation/reports", headers=mod_headers).json()["total"] == 0
    assert client.delete(f"/api/comments/{comment['id']}", headers=mod_headers).status_code == 200
    assert client.get(f"/api/posts/{post['id']}/comments").json()["total"] == 0
    assert client.get(f"/api/posts/{post['id']}").json()["comments_count"] == 0


def test_search_cyrillic_filters_and_pagination(client):
    headers, _ = register(client)
    mod_headers, _ = moderator(client)
    for index, category in enumerate(("community", "science", "community")):
        post = make_post(client, headers, title=f"Студенческая встреча номер {index}", category=category)
        publish(client, mod_headers, post["id"])
    result = client.get("/api/posts?search=СТУДЕНЧЕСКАЯ&page_size=2").json()
    assert result["total"] == 3 and len(result["items"]) == 2
    second = client.get("/api/posts?search=студенческая&page_size=2&page=2").json()
    assert len(second["items"]) == 1
    assert second["items"][0]["id"] not in [item["id"] for item in result["items"]]
    assert client.get("/api/posts?search=%25").json()["total"] == 0
    assert client.get("/api/posts?category=science").json()["total"] == 1
    assert client.get("/api/posts?category=nope").status_code == 422
    assert client.get("/api/posts?page=0").status_code == 422
    assert client.get("/api/posts?page_size=100").status_code == 200
    assert client.patch("/api/me", headers=headers, json={"interests": ["science"]}).status_code == 200
    assert client.get("/api/posts?feed=interests", headers=headers).json()["total"] == 1
    assert client.get("/api/posts?free=true").json()["total"] == 0
    assert client.get("/api/users?search=АВТОР").json()["total"] == 1


def test_event_validation_and_safe_urls(client):
    headers, _ = register(client)
    payload = {"type": "event", "title": "Встреча сообщества", "body": "Приглашаем студентов на открытую встречу в кампусе.", "category": "community"}
    assert client.post("/api/posts", headers=headers, json=payload).status_code == 422
    payload.update(event_start="2026-10-24T18:00:00+05:00", event_end="2026-10-24T17:00:00+05:00", location="Коворкинг")
    assert client.post("/api/posts", headers=headers, json=payload).status_code == 422
    payload.update(event_end="2026-10-24T20:00:00+05:00", cover_url="/media/covers/campus.jpg")
    assert client.post("/api/posts", headers=headers, json=payload).status_code == 201
    payload["cover_url"] = "javascript:alert(1)"
    assert client.post("/api/posts", headers=headers, json=payload).status_code == 422


def test_upload_verifies_content_and_reencodes_image(client):
    headers, _ = register(client)
    assert client.post("/api/uploads", headers=headers, files={"file": ("test.jpg", b"not an image", "image/jpeg")}).status_code == 422
    assert client.post("/api/uploads", headers=headers, files={"file": ("large.jpg", b"x" * (8 * 1024 * 1024 + 1), "image/jpeg")}).status_code == 413
    source = io.BytesIO()
    Image.new("RGBA", (100, 60), (100, 160, 200, 120)).save(source, "PNG")
    response = client.post("/api/uploads", headers=headers, files={"file": ("../../unsafe.png", source.getvalue(), "image/png")})
    assert response.status_code == 201, response.text
    url = response.json()["url"]
    assert url.startswith("/uploads/") and url.endswith(".jpg") and "unsafe" not in url
    image_response = client.get(url)
    assert image_response.status_code == 200
    assert Image.open(io.BytesIO(image_response.content)).format == "JPEG"
    rotated = io.BytesIO()
    exif = Image.Exif()
    exif[274] = 6  # A phone photo that requires a 90-degree orientation correction.
    Image.new("RGB", (80, 40), "blue").save(rotated, "JPEG", exif=exif)
    oriented = client.post("/api/uploads", headers=headers, files={"file": ("phone.jpg", rotated.getvalue(), "image/jpeg")}).json()
    result = Image.open(io.BytesIO(client.get(oriented["url"]).content))
    assert result.size == (40, 80)
    assert not result.getexif()


def test_notifications_are_private_and_mark_read(client):
    headers, _ = register(client)
    mod_headers, _ = moderator(client)
    post = make_post(client, headers)
    publish(client, mod_headers, post["id"])
    response = client.get("/api/notifications", headers=headers).json()
    assert response["total"] == 1 and response["unread_count"] == 1
    assert client.get("/api/notifications", headers=mod_headers).json()["total"] == 0
    assert client.put("/api/notifications/read", headers=headers).status_code == 200
    assert client.get("/api/notifications", headers=headers).json()["unread_count"] == 0


def test_failed_auth_attempts_are_rate_limited(client):
    for _ in range(30):
        response = client.post("/api/auth/login", json={"email": "missing@example.com", "password": "wrong"})
        assert response.status_code == 401
    response = client.post("/api/auth/login", json={"email": "missing@example.com", "password": "wrong"})
    assert response.status_code == 429


def test_demo_seed_is_repeatable_and_counts_are_real(tmp_path):
    path = tmp_path / "demo.sqlite3"
    app = create_app(path, seed_demo=True, upload_dir=tmp_path / "uploads")
    with TestClient(app) as client:
        assert client.get("/api/health").json()["demo"] is True
        feed = client.get("/api/posts?page_size=100").json()
        assert feed["total"] == 16
        assert all(post["status"] == "published" for post in feed["items"])
        login = client.post("/api/auth/login", json={"email": "student@pulse.local", "password": "Student123!"})
        assert login.status_code == 200
        headers = {"Authorization": "Bearer " + login.json()["token"]}
        assert client.get("/api/me/posts", headers=headers).json()["total"] == 2
        event = feed["items"][0]
        discussion = client.get(f"/api/posts/{event['id']}/comments").json()
        assert discussion["total"] == event["comments_count"] == 5
        assert sum(event["reactions"].values()) > 0
    with TestClient(create_app(path, seed_demo=True, upload_dir=tmp_path / "uploads")) as client:
        assert client.get("/api/posts").json()["total"] == 16
