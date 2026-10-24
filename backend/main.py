"""HTTP API. Run from the project root: python -m uvicorn backend.main:app."""
from __future__ import annotations

import json
import os
import secrets
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.concurrency import run_in_threadpool

from .database import connect, initialize
from .models import CommentCreate, Decision, Login, PostCreate, PostPatch, ProfilePatch, Reaction, Register, Report
from .security import hash_password, token_hash, verify_password
from .deployment import PublicGuard, PublicSettings
from .storage import ImageStorage
from .identity import ServerIdentity
from .ai_moderation import AiModerator, queue_review

ROOT = Path(__file__).resolve().parent
MAX_UPLOAD = 8 * 1024 * 1024


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def db(request: Request):
    connection = connect(request.app.state.db_path)
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


DB = Annotated[sqlite3.Connection, Depends(db)]


def current_user(connection: DB, authorization: Annotated[str | None, Header()] = None):
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(401, "Войдите в аккаунт", headers={"WWW-Authenticate": "Bearer"})
    user = connection.execute(
        "SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=? AND s.expires_at>?",
        (token_hash(token), now()),
    ).fetchone()
    if not user:
        raise HTTPException(401, "Сессия истекла. Войдите снова", headers={"WWW-Authenticate": "Bearer"})
    return user


OptionalUser = Annotated[sqlite3.Row | None, Depends(current_user)]


def require_user(user: OptionalUser):
    if user is None:
        raise HTTPException(401, "Войдите в аккаунт", headers={"WWW-Authenticate": "Bearer"})
    return user


User = Annotated[sqlite3.Row, Depends(require_user)]


def require_moderator(user: User):
    if user["role"] != "moderator":
        raise HTTPException(403, "Этот раздел доступен модераторам")
    return user


Moderator = Annotated[sqlite3.Row, Depends(require_moderator)]


def scalar(connection, query, args=()):
    return connection.execute(query, args).fetchone()[0]


def get_user(connection, user_id):
    row = connection.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "Профиль не найден")
    return row


def friend_ids(connection, user_id):
    return [row[0] for row in connection.execute("SELECT CASE WHEN user_low=? THEN user_high ELSE user_low END FROM friendships WHERE (user_low=? OR user_high=?) AND accepted_at IS NOT NULL", (user_id, user_id, user_id))]


def friendship_status(connection, user_id, viewer):
    if not viewer or viewer["id"] == user_id:
        return "none"
    low, high = sorted((user_id, viewer["id"]))
    row = connection.execute("SELECT * FROM friendships WHERE user_low=? AND user_high=?", (low, high)).fetchone()
    if row is None:
        return "none"
    if row["accepted_at"]:
        return "friends"
    return "outgoing" if row["requester_id"] == viewer["id"] else "incoming"


def user_json(connection, row, viewer=None):
    data = {key: row[key] for key in ("id", "name", "handle", "faculty", "course", "bio", "avatar_url", "avatar_color", "role")}
    # Email is only visible to its owner.
    data["email"] = row["email"] if viewer and viewer["id"] == row["id"] else ""
    data["interests"] = json.loads(row["interests"])
    data["followers_count"] = scalar(connection, "SELECT COUNT(*) FROM follows WHERE following_id=?", (row["id"],))
    data["following_count"] = scalar(connection, "SELECT COUNT(*) FROM follows WHERE follower_id=?", (row["id"],))
    data["publications_count"] = scalar(connection, "SELECT COUNT(*) FROM posts WHERE author_id=? AND status='published'", (row["id"],))
    data["is_following"] = bool(viewer and scalar(connection, "SELECT COUNT(*) FROM follows WHERE follower_id=? AND following_id=?", (viewer["id"], row["id"])))
    data["friends_count"] = scalar(connection, "SELECT COUNT(*) FROM friendships WHERE (user_low=? OR user_high=?) AND accepted_at IS NOT NULL", (row["id"], row["id"]))
    data["friendship_status"] = friendship_status(connection, row["id"], viewer)
    return data


def get_post(connection, post_id, viewer=None, public_only=False):
    row = connection.execute("SELECT * FROM posts WHERE id=?", (post_id,)).fetchone()
    if row is None or (row["status"] != "published" and (public_only or viewer is None or (viewer["id"] != row["author_id"] and viewer["role"] != "moderator"))):
        raise HTTPException(404, "Публикация не найдена")
    return row


def post_json(connection, row, viewer=None):
    data = dict(row)
    data['image_urls'] = json.loads(row['image_urls']) or ([row['cover_url']] if row['cover_url'] else [])
    data['ai_review'] = None
    if viewer and (viewer['id'] == row['author_id'] or viewer['role'] == 'moderator'):
        review = connection.execute('SELECT status,reason,model,images_checked,created_at FROM ai_reviews WHERE post_id=? AND revision=? ORDER BY id DESC LIMIT 1', (row['id'], row['updated_at'])).fetchone()
        if review:
            data['ai_review'] = dict(review)
    data.pop("author_id")
    data.pop("is_demo")
    data["category"] = dict(connection.execute("SELECT * FROM categories WHERE id=?", (row["category"],)).fetchone())
    data["excerpt"] = row["body"].replace("\n", " ")[:180] + ("…" if len(row["body"]) > 180 else "")
    data["author"] = user_json(connection, get_user(connection, row["author_id"]), viewer)
    data["reactions"] = {"like": 0, "fire": 0, "heart": 0, "clap": 0}
    data["reactions"].update({r["reaction"]: r["n"] for r in connection.execute("SELECT reaction,COUNT(*) n FROM reactions WHERE post_id=? GROUP BY reaction", (row["id"],))})
    my_reaction = connection.execute("SELECT reaction FROM reactions WHERE post_id=? AND user_id=?", (row["id"], viewer["id"])).fetchone() if viewer else None
    data["my_reaction"] = my_reaction[0] if my_reaction else None
    data["comments_count"] = scalar(connection, "SELECT COUNT(*) FROM comments WHERE post_id=?", (row["id"],))
    data["is_bookmarked"] = bool(viewer and scalar(connection, "SELECT COUNT(*) FROM bookmarks WHERE post_id=? AND user_id=?", (row["id"], viewer["id"])))
    data["is_attending"] = bool(viewer and scalar(connection, "SELECT COUNT(*) FROM attendance WHERE post_id=? AND user_id=?", (row["id"], viewer["id"])))
    data["attendees_count"] = scalar(connection, "SELECT COUNT(*) FROM attendance WHERE post_id=?", (row["id"],))
    friends = friend_ids(connection, viewer["id"]) if viewer else []
    attending_friends = [row for row in connection.execute("SELECT u.* FROM users u JOIN attendance a ON a.user_id=u.id WHERE a.post_id=? ORDER BY u.name", (row["id"],)) if row["id"] in friends] if friends else []
    data["friend_attendees"] = [user_json(connection, friend, viewer) for friend in attending_friends]
    data["friends_attending_count"] = len(attending_friends)
    return data


def comment_json(connection, row, viewer=None):
    return {"id": row["id"], "body": row["body"], "parent_id": row["parent_id"], "created_at": row["created_at"], "author": user_json(connection, get_user(connection, row["author_id"]), viewer)}


def paginated(items, total, page, page_size):
    return {"items": items, "total": total, "page": page, "page_size": page_size}


def notify(connection, user_id, title, body, post_id=None):
    connection.execute("INSERT INTO notifications(user_id,title,body,post_id,created_at) VALUES(?,?,?,?,?)", (user_id, title, body, post_id, now()))


def validate_category(connection, category):
    if not connection.execute("SELECT 1 FROM categories WHERE id=?", (category,)).fetchone():
        raise HTTPException(422, "Выберите категорию из списка")


def validate_event(data):
    if data["type"] == "event":
        if not data.get("event_start") or not data.get("location", ""):
            raise HTTPException(422, "Для мероприятия укажите дату начала и место")
        if data.get("event_end") and data["event_end"] < data["event_start"]:
            raise HTTPException(422, "Окончание мероприятия не может быть раньше начала")
    else:
        for key in ("event_start", "event_end", "location", "price", "registration_url"):
            data[key] = None


def create_app(db_path: str | Path | None = None, seed_demo: bool | None = None, upload_dir: str | Path | None = None, public_settings: PublicSettings | None = None, review_demo: bool | None = None) -> FastAPI:
    public = public_settings or PublicSettings(enabled=os.environ.get("PULSE_PUBLIC_MODE") == "true", proxy=os.environ.get("PULSE_TRUST_PROXY", "none"))
    database_path = Path(db_path or os.environ.get("PULSE_DB", str(ROOT / "data" / "pulse.sqlite3")))
    uploads = Path(upload_dir or os.environ.get("PULSE_UPLOAD_DIR", str(ROOT / "data" / "uploads")))
    uploads.mkdir(parents=True, exist_ok=True)
    media = ROOT / "media"
    media.mkdir(exist_ok=True)
    should_seed = seed_demo if seed_demo is not None else os.environ.get("PULSE_SEED_DEMO", "true").lower() == "true"
    review_mode = review_demo if review_demo is not None else os.environ.get("PULSE_REVIEW_DEMO") == "true"
    ai_enabled = os.environ.get('PULSE_AI_ENABLED') == 'true'
    identity_path = os.environ.get("PULSE_IDENTITY_KEY")
    identity = ServerIdentity(Path(identity_path), os.environ["PULSE_INSTANCE_ID"]) if identity_path else None
    endpoint_state = Path(os.environ["PULSE_ENDPOINT_STATE"]) if identity else None

    @asynccontextmanager
    async def lifespan(_app):
        initialize(database_path)
        from .seed import seed
        with connect(database_path) as connection:
            seed(connection, include_demo=should_seed)
            if public.enabled:
                for row in connection.execute("SELECT password_hash FROM users WHERE email LIKE '%@pulse.local'"):
                    if verify_password("Student123!", row[0]) or verify_password("Moderator123!", row[0]):
                        raise RuntimeError("Public mode refuses shared demo passwords. Run the public-server preparation first.")
            if review_mode:
                from .review_demo import prepare_review_users
                prepare_review_users(connection, storage=_app.state.image_storage,
                    photo_root=_app.state.chat_upload_dir, cover=media / "covers" / "coding.jpg")
        worker = AiModerator(database_path, os.environ.get('PULSE_OPENROUTER_KEY_FILE', str(database_path.parent / 'openrouter.key')),
            uploads, media, budget=float(os.environ.get('PULSE_AI_BUDGET_USD', '1.60'))) if ai_enabled else None
        if worker:
            worker.start()
        try:
            yield
        finally:
            if worker:
                worker.stop()

    app = FastAPI(title="Пульс УУНИТ", version="1.0.0", lifespan=lifespan,
                  docs_url=None if public.enabled else "/docs", redoc_url=None if public.enabled else "/redoc",
                  openapi_url=None if public.enabled else "/openapi.json")
    app.state.db_path = database_path
    app.state.seed_demo = should_seed
    app.state.chat_upload_dir = uploads.parent / "chat_uploads"
    app.state.image_storage = ImageStorage([uploads, app.state.chat_upload_dir],
        quota_bytes=int(os.environ.get("PULSE_MEDIA_QUOTA_MB", "1024")) * 1024 * 1024,
        minimum_free_bytes=1024 * 1024 * 1024 if public.enabled else 0)
    origins = [x.strip() for x in os.environ.get("PULSE_CORS_ORIGINS", "http://localhost:5173,http://localhost:3000,http://localhost:8080,http://127.0.0.1:5173").split(",") if x.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=False, allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"], allow_headers=["Authorization", "Content-Type"])
    app.add_middleware(PublicGuard, settings=public)
    app.mount("/uploads", StaticFiles(directory=str(uploads)), name="uploads")
    app.mount("/media", StaticFiles(directory=str(media)), name="media")

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request, exc):
        labels = {"name": "имя", "handle": "имя пользователя", "avatar_color": "цвет профиля", "email": "почта", "password": "пароль", "title": "заголовок", "body": "текст", "faculty": "институт или факультет", "course": "курс", "category": "категория", "reason": "причина", "file": "изображение"}
        errors = []
        for error in exc.errors():
            field = str(error["loc"][-1])
            label = labels.get(field, field)
            kind = error["type"]
            message = "Проверьте значение поля"
            if kind == "missing":
                message = "Заполните поле"
            elif kind == "extra_forbidden":
                message = "Это поле нельзя изменить"
            elif "too_short" in kind:
                message = f"Минимум {error.get('ctx', {}).get('min_length', 1)} символов"
            elif "too_long" in kind:
                message = f"Максимум {error.get('ctx', {}).get('max_length', 0)} символов"
            elif kind == "value_error":
                message = str(error.get("ctx", {}).get("error", "Некорректное значение"))
            errors.append({"field": field, "message": message})
        first = errors[0] if errors else {"field": "", "message": "Проверьте введённые данные"}
        return JSONResponse(status_code=422, content={"detail": f"{labels.get(first['field'], first['field']).capitalize()}: {first['message']}", "errors": errors})

    @app.exception_handler(sqlite3.OperationalError)
    async def concurrent_update_error(_request, exc):
        if "locked" in str(exc).lower() or "busy" in str(exc).lower():
            return JSONResponse(status_code=409, content={"detail": "Данные изменились. Обновите экран и повторите действие"})
        raise exc

    @app.get("/api/health")
    def health(connection: DB):
        connection.execute("SELECT 1")
        return {"status": "ok", "service": "pulse", "version": "1.0.0", "public": public.enabled, "demo": should_seed or review_mode, "demo_notice": "Демонстрационные аккаунты, публикации и мероприятия вымышлены. Приложение не является официальным сервисом УУНИТ." if should_seed or review_mode else None}

    @app.get("/api/server-proof")
    def server_proof(nonce: Annotated[str, Query(min_length=32, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")]):
        if identity is None:
            raise HTTPException(404, "Подтверждение сервера не настроено")
        try:
            origin = json.loads(endpoint_state.read_text(encoding="utf-8"))["url"]
            if not origin or not origin.startswith("https://"):
                raise ValueError("No public endpoint")
        except (OSError, ValueError, KeyError):
            raise HTTPException(503, "Подключение сервера обновляется")
        return identity.proof(nonce, origin)

    def auth_rate_limit(connection, request):
        address = request.scope.get("state", {}).get("pulse_address", request.client.host if request.client else "unknown")
        cutoff = iso(datetime.now(timezone.utc) - timedelta(minutes=15))
        connection.execute("DELETE FROM auth_attempts WHERE created_at<?", (cutoff,))
        if scalar(connection, "SELECT COUNT(*) FROM auth_attempts WHERE address=?", (address,)) >= 30:
            raise HTTPException(429, "Слишком много попыток входа. Попробуйте через 15 минут", headers={"Retry-After": "900"})
        connection.execute("INSERT INTO auth_attempts(address,created_at) VALUES(?,?)", (address, now()))
        # Persist failed attempts even when the request later raises HTTPException.
        connection.commit()

    def session(connection, user):
        raw = secrets.token_urlsafe(48)
        expires = iso(datetime.now(timezone.utc) + timedelta(days=14))
        connection.execute("DELETE FROM sessions WHERE expires_at<=?", (now(),))
        connection.execute("INSERT INTO sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)", (token_hash(raw), user["id"], now(), expires))
        return {"token": raw, "token_type": "bearer", "expires_at": expires, "user": user_json(connection, user, user)}

    @app.post("/api/auth/register", status_code=201)
    def register(body: Register, request: Request, connection: DB):
        auth_rate_limit(connection, request)
        if connection.execute("SELECT 1 FROM users WHERE email=?", (body.email,)).fetchone():
            raise HTTPException(409, "Аккаунт с такой почтой уже существует")
        handle = "student_" + secrets.token_hex(4)
        cursor = connection.execute("INSERT INTO users(email,password_hash,name,handle,faculty,course,created_at) VALUES(?,?,?,?,?,?,?)", (body.email, hash_password(body.password), body.name, handle, body.faculty, body.course, now()))
        if review_mode:
            from .review_demo import onboard_user
            onboard_user(connection, cursor.lastrowid, storage=app.state.image_storage,
                photo_root=app.state.chat_upload_dir, cover=media / "covers" / "coding.jpg")
        return session(connection, get_user(connection, cursor.lastrowid))

    @app.post("/api/auth/login")
    def login(body: Login, request: Request, connection: DB):
        auth_rate_limit(connection, request)
        user = connection.execute("SELECT * FROM users WHERE email=?", (body.email.lower(),)).fetchone()
        # A dummy hash keeps timing similar for unknown addresses.
        candidate = user["password_hash"] if user else request.app.state.dummy_password
        if not verify_password(body.password, candidate) or user is None:
            raise HTTPException(401, "Неверная почта или пароль")
        return session(connection, user)

    app.state.dummy_password = hash_password(secrets.token_urlsafe(20))

    @app.post("/api/auth/logout")
    def logout(user: User, connection: DB, authorization: Annotated[str, Header()]):
        connection.execute("DELETE FROM sessions WHERE token_hash=?", (token_hash(authorization.partition(" ")[2]),))
        return {"ok": True}

    @app.get("/api/me")
    def me(user: User, connection: DB):
        return user_json(connection, user, user)

    @app.patch("/api/me")
    def update_me(body: ProfilePatch, user: User, connection: DB):
        data = body.model_dump(exclude_unset=True)
        for key in ("name", "handle", "avatar_color", "faculty", "bio", "interests"):
            if key in data and data[key] is None:
                raise HTTPException(422, "Заполните обязательные поля профиля")
        if "handle" in data and connection.execute("SELECT 1 FROM users WHERE LOWER(handle)=? AND id<>?", (data["handle"], user["id"])).fetchone():
            raise HTTPException(409, "Это имя пользователя уже занято")
        if "interests" in data:
            for category in data["interests"]:
                validate_category(connection, category)
            data["interests"] = json.dumps(list(dict.fromkeys(data["interests"])), ensure_ascii=False)
        if data:
            try:
                connection.execute("UPDATE users SET " + ",".join(f"{key}=?" for key in data) + " WHERE id=?", (*data.values(), user["id"]))
            except sqlite3.IntegrityError:
                raise HTTPException(409, "Это имя пользователя уже занято")
        return user_json(connection, get_user(connection, user["id"]), user)

    @app.get("/api/users")
    def users(connection: DB, user: OptionalUser, search: str = Query(default="", max_length=120), page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        # SQLite LOWER is ASCII-only. Search Russian names in Python for this small campus directory.
        rows = [row for row in connection.execute("SELECT * FROM users ORDER BY id") if not search or search.casefold() in (row["name"] + " " + row["handle"] + " " + row["faculty"]).casefold()]
        return paginated([user_json(connection, row, user) for row in rows[(page - 1) * page_size:page * page_size]], len(rows), page, page_size)

    @app.get("/api/users/{user_id}")
    def user_detail(user_id: int, connection: DB, user: OptionalUser):
        return user_json(connection, get_user(connection, user_id), user)

    @app.get("/api/friends")
    def friends(connection: DB, user: User, page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        ids = friend_ids(connection, user["id"])
        rows = sorted([get_user(connection, friend_id) for friend_id in ids], key=lambda row: row["name"].casefold())
        return paginated([user_json(connection, row, user) for row in rows[(page - 1) * page_size:page * page_size]], len(rows), page, page_size)

    @app.get("/api/friends/requests")
    def friend_requests(connection: DB, user: User):
        rows = connection.execute("SELECT * FROM friendships WHERE (user_low=? OR user_high=?) AND accepted_at IS NULL ORDER BY created_at DESC", (user["id"], user["id"])).fetchall()
        result = {"incoming": [], "outgoing": []}
        for row in rows:
            other_id = row["user_high"] if row["user_low"] == user["id"] else row["user_low"]
            result["outgoing" if row["requester_id"] == user["id"] else "incoming"].append(user_json(connection, get_user(connection, other_id), user))
        return result

    @app.put("/api/users/{user_id}/friend-request")
    def request_friendship(user_id: int, connection: DB, user: User):
        target = get_user(connection, user_id)
        if user_id == user["id"]:
            raise HTTPException(422, "Нельзя отправить заявку самому себе")
        low, high = sorted((user_id, user["id"]))
        cursor = connection.execute("INSERT OR IGNORE INTO friendships(user_low,user_high,requester_id,created_at) VALUES(?,?,?,?)", (low, high, user["id"], now()))
        if cursor.rowcount:
            notify(connection, user_id, "Заявка в друзья", f"{user['name']} хочет добавить вас в друзья")
        return user_json(connection, target, user)

    @app.post("/api/users/{user_id}/friend-request/accept")
    def accept_friendship(user_id: int, connection: DB, user: User):
        target = get_user(connection, user_id)
        if user_id == user["id"]:
            raise HTTPException(422, "Нельзя добавить себя в друзья")
        low, high = sorted((user_id, user["id"]))
        row = connection.execute("SELECT * FROM friendships WHERE user_low=? AND user_high=?", (low, high)).fetchone()
        if row and row["accepted_at"]:
            return user_json(connection, target, user)
        if row is None or row["requester_id"] != user_id:
            raise HTTPException(409, "Входящая заявка от этого пользователя не найдена")
        connection.execute("UPDATE friendships SET accepted_at=? WHERE user_low=? AND user_high=? AND accepted_at IS NULL", (now(), low, high))
        notify(connection, user_id, "Заявка принята", f"{user['name']} добавил вас в друзья")
        return user_json(connection, target, user)

    @app.delete("/api/users/{user_id}/friendship")
    def remove_friendship(user_id: int, connection: DB, user: User):
        target = get_user(connection, user_id)
        low, high = sorted((user_id, user["id"]))
        connection.execute("DELETE FROM friendships WHERE user_low=? AND user_high=?", (low, high))
        return user_json(connection, target, user)

    @app.put("/api/users/{user_id}/follow")
    def follow(user_id: int, connection: DB, user: User):
        target = get_user(connection, user_id)
        if user_id == user["id"]:
            raise HTTPException(422, "Нельзя подписаться на свой профиль")
        connection.execute("INSERT OR IGNORE INTO follows(follower_id,following_id) VALUES(?,?)", (user["id"], user_id))
        return user_json(connection, target, user)

    @app.delete("/api/users/{user_id}/follow")
    def unfollow(user_id: int, connection: DB, user: User):
        target = get_user(connection, user_id)
        connection.execute("DELETE FROM follows WHERE follower_id=? AND following_id=?", (user["id"], user_id))
        return user_json(connection, target, user)

    @app.get("/api/categories")
    def categories(connection: DB, user: OptionalUser):
        topics = json.loads(user['interests']) if user else []
        return [dict(row) | {'is_following': row['id'] in topics} for row in connection.execute("SELECT * FROM categories ORDER BY rowid")]

    @app.put('/api/categories/{category_id}/follow')
    def follow_topic(category_id: str, connection: DB, user: User):
        validate_category(connection, category_id)
        topics = list(dict.fromkeys([*json.loads(user['interests']), category_id]))
        connection.execute('UPDATE users SET interests=? WHERE id=?', (json.dumps(topics), user['id']))
        current = get_user(connection, user['id'])
        return user_json(connection, current, current)

    @app.delete('/api/categories/{category_id}/follow')
    def unfollow_topic(category_id: str, connection: DB, user: User):
        validate_category(connection, category_id)
        topics = [item for item in json.loads(user['interests']) if item != category_id]
        connection.execute('UPDATE users SET interests=? WHERE id=?', (json.dumps(topics), user['id']))
        current = get_user(connection, user['id'])
        return user_json(connection, current, current)

    def list_posts(connection, user, where, args, page, page_size, search="", order="COALESCE(p.published_at,p.created_at) DESC, p.id DESC"):
        # Case-insensitive Cyrillic search is registered per connection; all filters remain parameterized.
        connection.create_function("CASEFOLD", 1, lambda value: (value or "").casefold())
        if search:
            where.append("(CASEFOLD(p.title) LIKE ? ESCAPE '\\' OR CASEFOLD(p.body) LIKE ? ESCAPE '\\')")
            escaped = search.casefold().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            args.extend(["%" + escaped + "%"] * 2)
        condition = " AND ".join(where)
        total = scalar(connection, "SELECT COUNT(*) FROM posts p WHERE " + condition, args)
        rows = connection.execute("SELECT p.* FROM posts p WHERE " + condition + " ORDER BY " + order + " LIMIT ? OFFSET ?", (*args, page_size, (page - 1) * page_size)).fetchall()
        return paginated([post_json(connection, row, user) for row in rows], total, page, page_size)

    @app.get("/api/posts")
    def posts(connection: DB, user: OptionalUser, category: str | None = None, search: str = Query(default="", max_length=200), type: Literal["news", "event"] | None = None, period: Literal["today", "week"] | None = None, feed: Literal["following", "for_you", "interests", "friends"] | None = None, saved: bool = False, free: bool = False, page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        where, args = ["p.status='published'"], []
        if category:
            validate_category(connection, category)
            where.append("p.category=?")
            args.append(category)
        if type:
            where.append("p.type=?")
            args.append(type)
        order = "p.event_start ASC, p.id DESC" if period else "COALESCE(p.published_at,p.created_at) DESC, p.id DESC"
        if feed in ("following", "for_you", "interests", "friends") or saved:
            if user is None:
                raise HTTPException(401, "Войдите, чтобы открыть персональную ленту")
        if feed == "following":
            topics = json.loads(user['interests'])
            topic_sql = ' OR p.category IN (' + ','.join('?' for _ in topics) + ')' if topics else ''
            where.append("(p.author_id IN (SELECT following_id FROM follows WHERE follower_id=?)" + topic_sql + ')')
            args.append(user["id"])
            args.extend(topics)
        if feed == "friends":
            friends = friend_ids(connection, user["id"])
            if not friends:
                return paginated([], 0, page, page_size)
            friend_set = ",".join(str(friend_id) for friend_id in friends)  # integer IDs from the database, never user input
            count = f"(SELECT COUNT(*) FROM attendance a WHERE a.post_id=p.id AND a.user_id IN ({friend_set}))"
            where.extend(["p.type='event'", "p.event_start>=?", count + ">0"])
            args.append(now())
            order = count + " DESC,p.event_start ASC,p.id DESC"
        if feed in ("for_you", "interests"):
            interests = json.loads(user["interests"])
            if interests:
                where.append("p.category IN (" + ",".join("?" for _ in interests) + ")")
                args.extend(interests)
        if saved:
            where.append("p.id IN (SELECT post_id FROM bookmarks WHERE user_id=?)")
            args.append(user["id"])
        if free:
            where.append("p.type='event' AND (p.price IS NULL OR p.price='' OR p.price='0' OR p.price='Бесплатно')")
        if period:
            # Ufa uses UTC+5 year-round; fixed offset avoids OS timezone database differences.
            local = datetime.now(timezone(timedelta(hours=5)))
            start = local.replace(hour=0, minute=0, second=0, microsecond=0)
            end = start + timedelta(days=1 if period == "today" else 7)
            where.extend(["p.type='event'", "p.event_start>=?", "p.event_start<?"])
            args.extend([iso(start), iso(end)])
        return list_posts(connection, user, where, args, page, page_size, search, order)

    @app.get("/api/me/posts")
    def my_posts(connection: DB, user: User, status: Literal["draft", "pending", "published", "changes_requested", "rejected"] | None = None, page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        where, args = ["p.author_id=?"], [user["id"]]
        if status:
            where.append("p.status=?")
            args.append(status)
        return list_posts(connection, user, where, args, page, page_size, order="p.updated_at DESC, p.id DESC")

    @app.get("/api/users/{user_id}/posts")
    def user_posts(user_id: int, connection: DB, user: OptionalUser, page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        get_user(connection, user_id)
        return list_posts(connection, user, ["p.author_id=?", "p.status='published'"], [user_id], page, page_size)

    @app.get("/api/posts/{post_id}")
    def post_detail(post_id: int, connection: DB, user: OptionalUser):
        return post_json(connection, get_post(connection, post_id, user), user)

    @app.post("/api/posts", status_code=201)
    def create_post(body: PostCreate, connection: DB, user: User):
        data = body.model_dump()
        submit = data.pop("submit")
        images = data.get('image_urls')
        if images is None:
            images = [data['cover_url']] if data['cover_url'] else []
        data['image_urls'] = json.dumps(images)
        data['cover_url'] = images[0] if images else None
        validate_category(connection, data["category"])
        data["event_start"], data["event_end"] = iso(data["event_start"]), iso(data["event_end"])
        validate_event(data)
        data.update(author_id=user["id"], status="pending" if submit else "draft", created_at=now(), updated_at=now())
        cursor = connection.execute("INSERT INTO posts(" + ",".join(data) + ") VALUES(" + ",".join("?" for _ in data) + ")", tuple(data.values()))
        if submit:
            connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,created_at) VALUES(?,?,?,?)", (cursor.lastrowid, user["id"], "submitted", now()))
            queue_review(connection, cursor.lastrowid, ai_enabled)
        return post_json(connection, get_post(connection, cursor.lastrowid, user), user)

    @app.patch("/api/posts/{post_id}")
    def edit_post(post_id: int, body: PostPatch, connection: DB, user: User):
        previous = get_post(connection, post_id, user)
        if previous["author_id"] != user["id"]:
            raise HTTPException(403, "Изменять публикацию может только автор")
        patch = body.model_dump(exclude_unset=True)
        submit = patch.pop("submit", None)
        if 'image_urls' in patch:
            images = patch['image_urls']
            patch['cover_url'] = images[0] if images else None
            patch['image_urls'] = json.dumps(images)
        elif 'cover_url' in patch:
            patch['image_urls'] = json.dumps([patch['cover_url']] if patch['cover_url'] else [])
        if not patch and submit is None:
            return post_json(connection, previous, user)
        for key in ("title", "body", "category", "type"):
            if key in patch and patch[key] is None:
                raise HTTPException(422, "Обязательные поля публикации не могут быть пустыми")
        if "category" in patch:
            validate_category(connection, patch["category"])
        for field in ("event_start", "event_end"):
            if field in patch:
                patch[field] = iso(patch[field])
        merged = dict(previous) | patch
        validate_event(merged)
        if merged["type"] == "news":
            patch.update({key: None for key in ("event_start", "event_end", "location", "price", "registration_url")})
        if patch or submit is not None:
            # Every content change invalidates the previous decision, including edits by moderators.
            next_status = "draft" if submit is False else "pending" if previous["status"] in ("published", "pending") or submit else "draft"
            patch.update(status=next_status, moderation_reason=None, published_at=None, updated_at=now())
            connection.execute("UPDATE posts SET " + ",".join(f"{key}=?" for key in patch) + " WHERE id=?", (*patch.values(), post_id))
            connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,reason,created_at) VALUES(?,?,?,?,?)", (post_id, user["id"], "edited", "После изменения публикация проходит проверку заново", now()))
            if next_status == 'pending':
                queue_review(connection, post_id, ai_enabled)
        return post_json(connection, get_post(connection, post_id, user), user)

    @app.post("/api/posts/{post_id}/submit")
    def submit_post(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        if post["author_id"] != user["id"]:
            raise HTTPException(403, "Отправить публикацию может только автор")
        if post["status"] in ("published", "pending"):
            raise HTTPException(409, "Публикация уже отправлена на проверку или опубликована")
        validate_event(dict(post))
        connection.execute("UPDATE posts SET status='pending',moderation_reason=NULL,published_at=NULL,updated_at=? WHERE id=?", (now(), post_id))
        connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,created_at) VALUES(?,?,?,?)", (post_id, user["id"], "submitted", now()))
        queue_review(connection, post_id, ai_enabled)
        return post_json(connection, get_post(connection, post_id, user), user)

    @app.post('/api/posts/{post_id}/appeal')
    def appeal_ai(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        review = connection.execute('SELECT * FROM ai_reviews WHERE post_id=? AND revision=?', (post_id, post['updated_at'])).fetchone()
        if post['author_id'] != user['id']:
            raise HTTPException(403, 'Запросить перепроверку может только автор')
        if post['status'] != 'changes_requested' or not review or review['status'] != 'changes_requested':
            raise HTTPException(409, 'Для этой публикации нет решения ИИ, которое можно перепроверить')
        connection.execute("UPDATE ai_reviews SET status='appealed' WHERE id=?", (review['id'],))
        connection.execute("UPDATE posts SET status='pending',moderation_reason=NULL WHERE id=?", (post_id,))
        connection.execute('INSERT INTO moderation_history(post_id,actor_id,decision,reason,created_at) VALUES(?,?,?,?,?)', (post_id, user['id'], 'appealed', 'Автор запросил перепроверку решения ИИ человеком', now()))
        return post_json(connection, get_post(connection, post_id, user), user)

    @app.put("/api/posts/{post_id}/bookmark")
    def bookmark(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user, public_only=True)
        connection.execute("INSERT OR IGNORE INTO bookmarks(user_id,post_id) VALUES(?,?)", (user["id"], post_id))
        return post_json(connection, post, user)

    @app.delete("/api/posts/{post_id}/bookmark")
    def unbookmark(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        connection.execute("DELETE FROM bookmarks WHERE user_id=? AND post_id=?", (user["id"], post_id))
        return post_json(connection, post, user)

    @app.put("/api/posts/{post_id}/reaction")
    def react(post_id: int, body: Reaction, connection: DB, user: User):
        post = get_post(connection, post_id, user, public_only=True)
        connection.execute("INSERT INTO reactions(user_id,post_id,reaction) VALUES(?,?,?) ON CONFLICT(user_id,post_id) DO UPDATE SET reaction=excluded.reaction", (user["id"], post_id, body.reaction))
        return post_json(connection, post, user)

    @app.delete("/api/posts/{post_id}/reaction")
    def unreact(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        connection.execute("DELETE FROM reactions WHERE user_id=? AND post_id=?", (user["id"], post_id))
        return post_json(connection, post, user)

    @app.put("/api/posts/{post_id}/attendance")
    def attend(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user, public_only=True)
        if post["type"] != "event":
            raise HTTPException(422, "Участие можно отметить только у мероприятия")
        connection.execute("INSERT OR IGNORE INTO attendance(user_id,post_id) VALUES(?,?)", (user["id"], post_id))
        return post_json(connection, post, user)

    @app.delete("/api/posts/{post_id}/attendance")
    def unattend(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        connection.execute("DELETE FROM attendance WHERE user_id=? AND post_id=?", (user["id"], post_id))
        return post_json(connection, post, user)

    @app.get("/api/posts/{post_id}/comments")
    def comments(post_id: int, connection: DB, user: OptionalUser, page: int = Query(default=1, ge=1), page_size: int = Query(default=30, ge=1, le=100)):
        get_post(connection, post_id, user)
        rows = connection.execute("SELECT * FROM comments WHERE post_id=? ORDER BY created_at,id LIMIT ? OFFSET ?", (post_id, page_size, (page - 1) * page_size)).fetchall()
        return paginated([comment_json(connection, row, user) for row in rows], scalar(connection, "SELECT COUNT(*) FROM comments WHERE post_id=?", (post_id,)), page, page_size)

    @app.post("/api/posts/{post_id}/comments", status_code=201)
    def add_comment(post_id: int, body: CommentCreate, connection: DB, user: User):
        post = get_post(connection, post_id, user, public_only=True)
        if body.parent_id and not connection.execute("SELECT 1 FROM comments WHERE id=? AND post_id=?", (body.parent_id, post_id)).fetchone():
            raise HTTPException(422, "Комментарий для ответа не найден в этом обсуждении")
        cursor = connection.execute("INSERT INTO comments(post_id,author_id,body,created_at,parent_id) VALUES(?,?,?,?,?)", (post_id, user["id"], body.body, now(), body.parent_id))
        if post["author_id"] != user["id"]:
            notify(connection, post["author_id"], "Новый комментарий", f"{user['name']} оставил комментарий к публикации «{post['title']}»", post_id)
        return comment_json(connection, connection.execute("SELECT * FROM comments WHERE id=?", (cursor.lastrowid,)).fetchone(), user)

    @app.delete("/api/comments/{comment_id}")
    def delete_comment(comment_id: int, connection: DB, user: User):
        comment = connection.execute("SELECT * FROM comments WHERE id=?", (comment_id,)).fetchone()
        if not comment:
            raise HTTPException(404, "Комментарий не найден")
        if comment["author_id"] != user["id"] and user["role"] != "moderator":
            raise HTTPException(403, "Удалить комментарий может его автор или модератор")
        connection.execute("DELETE FROM comments WHERE id=?", (comment_id,))
        return {"ok": True}

    @app.post("/api/comments/{comment_id}/report", status_code=201)
    def report_comment(comment_id: int, body: Report, connection: DB, user: User):
        comment = connection.execute("SELECT * FROM comments WHERE id=?", (comment_id,)).fetchone()
        if not comment:
            raise HTTPException(404, "Комментарий не найден")
        get_post(connection, comment["post_id"], user, public_only=True)
        connection.execute("INSERT INTO comment_reports(comment_id,user_id,reason,created_at) VALUES(?,?,?,?) ON CONFLICT(comment_id,user_id) DO UPDATE SET reason=excluded.reason,status='open',created_at=excluded.created_at", (comment_id, user["id"], body.reason, now()))
        return {"ok": True, "message": "Жалоба отправлена модератору"}

    @app.get("/api/moderation/posts")
    def moderation_posts(connection: DB, user: Moderator, status: Literal["pending", "published", "changes_requested", "rejected", "draft"] = "pending", page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=100)):
        return list_posts(connection, user, ["p.status=?"], [status], page, page_size, order="p.updated_at ASC,p.id ASC")

    @app.post("/api/moderation/posts/{post_id}/decision")
    def moderation_decision(post_id: int, body: Decision, connection: DB, user: Moderator):
        post = get_post(connection, post_id, user)
        if post["author_id"] == user["id"]:
            raise HTTPException(403, "Свою публикацию должен проверить другой модератор")
        if post["status"] != "pending":
            raise HTTPException(409, "Публикация уже обработана или ещё не отправлена на проверку")
        if body.expected_updated_at != post["updated_at"]:
            raise HTTPException(409, "Автор изменил публикацию после открытия проверки. Обновите экран и проверьте новую версию")
        if body.decision != "publish" and not body.reason:
            raise HTTPException(422, "Укажите причину, чтобы автор понимал, что исправить")
        status = {"publish": "published", "changes_requested": "changes_requested", "reject": "rejected"}[body.decision]
        published_at = now() if status == "published" else None
        updated = connection.execute("UPDATE posts SET status=?,moderation_reason=?,published_at=?,updated_at=? WHERE id=? AND status='pending' AND updated_at=?", (status, body.reason, published_at, now(), post_id, post["updated_at"]))
        if updated.rowcount != 1:
            raise HTTPException(409, "Публикация изменилась во время проверки. Обновите экран")
        connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,reason,created_at) VALUES(?,?,?,?,?)", (post_id, user["id"], body.decision, body.reason, now()))
        title = {"published": "Публикация одобрена", "changes_requested": "Нужны изменения", "rejected": "Публикация отклонена"}[status]
        notify(connection, post["author_id"], title, body.reason or f"«{post['title']}» появилась в ленте", post_id)
        return post_json(connection, get_post(connection, post_id, user), user)

    @app.get("/api/moderation/posts/{post_id}/history")
    def moderation_history(post_id: int, connection: DB, user: User):
        post = get_post(connection, post_id, user)
        if post["author_id"] != user["id"] and user["role"] != "moderator":
            raise HTTPException(403, "История доступна автору и модераторам")
        rows = connection.execute("SELECT * FROM moderation_history WHERE post_id=? ORDER BY created_at,id", (post_id,)).fetchall()
        return {"items": [{"id": row["id"], "decision": row["decision"], "action": {"publish": "approve", "changes_requested": "return"}.get(row["decision"], row["decision"]), "reason": row["reason"], "created_at": row["created_at"], "actor": user_json(connection, get_user(connection, row["actor_id"]), user), "moderator": user_json(connection, get_user(connection, row["actor_id"]), user)} for row in rows]}

    @app.get("/api/moderation/reports")
    def reports(connection: DB, user: Moderator, status: Literal["open", "resolved"] = "open", page: int = Query(default=1, ge=1), page_size: int = Query(default=20, ge=1, le=50)):
        rows = connection.execute("SELECT * FROM comment_reports WHERE status=? ORDER BY created_at LIMIT ? OFFSET ?", (status, page_size, (page - 1) * page_size)).fetchall()
        items = []
        for row in rows:
            comment = connection.execute("SELECT * FROM comments WHERE id=?", (row["comment_id"],)).fetchone()
            items.append({"id": row["id"], "reason": row["reason"], "status": row["status"], "created_at": row["created_at"], "reporter": user_json(connection, get_user(connection, row["user_id"]), user), "post_id": comment["post_id"], "comment": comment_json(connection, comment, user)})
        return paginated(items, scalar(connection, "SELECT COUNT(*) FROM comment_reports WHERE status=?", (status,)), page, page_size)

    @app.post("/api/moderation/reports/{report_id}/resolve")
    def resolve_report(report_id: int, connection: DB, user: Moderator):
        if not connection.execute("SELECT 1 FROM comment_reports WHERE id=?", (report_id,)).fetchone():
            raise HTTPException(404, "Жалоба не найдена")
        connection.execute("UPDATE comment_reports SET status='resolved' WHERE id=?", (report_id,))
        return {"ok": True}

    @app.get("/api/notifications")
    def notifications(connection: DB, user: User, page: int = Query(default=1, ge=1), page_size: int = Query(default=30, ge=1, le=100)):
        rows = connection.execute("SELECT * FROM notifications WHERE user_id=? ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?", (user["id"], page_size, (page - 1) * page_size)).fetchall()
        result = paginated([{key: (bool(row[key]) if key == "is_read" else row[key]) for key in ("id", "title", "body", "post_id", "created_at", "is_read")} for row in rows], scalar(connection, "SELECT COUNT(*) FROM notifications WHERE user_id=?", (user["id"],)), page, page_size)
        result["unread_count"] = scalar(connection, "SELECT COUNT(*) FROM notifications WHERE user_id=? AND is_read=0", (user["id"],))
        return result

    @app.put("/api/notifications/read")
    def mark_notifications_read(connection: DB, user: User):
        connection.execute("UPDATE notifications SET is_read=1 WHERE user_id=?", (user["id"],))
        return {"ok": True}

    @app.post("/api/uploads", status_code=201)
    async def upload(user: User, file: Annotated[UploadFile, File()]):
        content = await file.read(MAX_UPLOAD + 1)
        await file.close()
        if len(content) > MAX_UPLOAD:
            raise HTTPException(413, "Изображение должно быть не больше 8 МБ")
        name = await run_in_threadpool(app.state.image_storage.save, content, uploads)
        public_base = os.environ.get("PULSE_PUBLIC_BASE_URL", "").rstrip("/")
        return {"url": public_base + "/uploads/" + name}

    from .chat import register_chat_routes
    register_chat_routes(app, db, require_user, user_json, get_user, now)
    return app


app = create_app()
