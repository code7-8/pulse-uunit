"""Private one-to-one conversations and authenticated photo attachments."""
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field, model_validator


class ChatCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    user_id: int = Field(gt=0)


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    body: str = Field(default="", max_length=4000)
    image_url: str | None = Field(default=None, max_length=300)

    @model_validator(mode="after")
    def has_content(self):
        if not self.body and not self.image_url:
            raise ValueError("Введите сообщение или выберите фотографию")
        return self


def register_chat_routes(app, db_dependency, user_dependency, user_json, get_user, now):
    photo_root = Path(app.state.chat_upload_dir)
    photo_root.mkdir(parents=True, exist_ok=True)
    max_upload = 8 * 1024 * 1024

    def are_friends(connection, first, second):
        low, high = sorted((first, second))
        return connection.execute(
            "SELECT 1 FROM friendships WHERE user_low=? AND user_high=? AND accepted_at IS NOT NULL",
            (low, high),
        ).fetchone() is not None

    def conversation(connection, chat_id, user):
        row = connection.execute("SELECT * FROM conversations WHERE id=?", (chat_id,)).fetchone()
        if row is None or user["id"] not in (row["user_low"], row["user_high"]):
            raise HTTPException(404, "Переписка не найдена")
        return row

    def peer_id(row, user):
        return row["user_high"] if row["user_low"] == user["id"] else row["user_low"]

    def message_json(row):
        return {key: row[key] for key in ("id", "conversation_id", "sender_id", "body", "image_url", "created_at", "read_at")}

    def chat_json(connection, row, user):
        other_id = peer_id(row, user)
        last = connection.execute("SELECT * FROM messages WHERE conversation_id=? ORDER BY id DESC LIMIT 1", (row["id"],)).fetchone()
        unread = connection.execute(
            "SELECT COUNT(*) FROM messages WHERE conversation_id=? AND sender_id<>? AND read_at IS NULL",
            (row["id"], user["id"]),
        ).fetchone()[0]
        return {
            "id": row["id"], "peer": user_json(connection, get_user(connection, other_id), user),
            "created_at": row["created_at"], "last_message": message_json(last) if last else None,
            "unread_count": unread, "can_send": are_friends(connection, user["id"], other_id),
        }

    @app.get("/api/chats")
    def chats(connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        rows = connection.execute(
            "SELECT c.* FROM conversations c WHERE c.user_low=? OR c.user_high=? "
            "ORDER BY COALESCE((SELECT MAX(m.created_at) FROM messages m WHERE m.conversation_id=c.id),c.created_at) DESC,c.id DESC",
            (user["id"], user["id"]),
        ).fetchall()
        return {"items": [chat_json(connection, row, user) for row in rows], "total": len(rows)}

    @app.post("/api/chats")
    def open_chat(body: ChatCreate, connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        if body.user_id == user["id"]:
            raise HTTPException(422, "Выберите собеседника")
        get_user(connection, body.user_id)
        low, high = sorted((user["id"], body.user_id))
        existing = connection.execute("SELECT * FROM conversations WHERE user_low=? AND user_high=?", (low, high)).fetchone()
        if existing:
            return chat_json(connection, existing, user)
        if not are_friends(connection, user["id"], body.user_id):
            raise HTTPException(403, "Начать переписку можно после принятия заявки в друзья")
        connection.execute("INSERT OR IGNORE INTO conversations(user_low,user_high,created_at) VALUES(?,?,?)", (low, high, now()))
        return chat_json(connection, connection.execute("SELECT * FROM conversations WHERE user_low=? AND user_high=?", (low, high)).fetchone(), user)

    @app.get("/api/chats/{chat_id}/messages")
    def messages(chat_id: int, after_id: int | None = Query(default=None, ge=0), before_id: int | None = Query(default=None, gt=0), page_size: int = Query(default=100, ge=1, le=100), connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        conversation(connection, chat_id, user)
        if after_id is not None:
            rows = connection.execute("SELECT * FROM messages WHERE conversation_id=? AND id>? ORDER BY id LIMIT ?", (chat_id, after_id, page_size)).fetchall()
        elif before_id is not None:
            rows = list(reversed(connection.execute("SELECT * FROM messages WHERE conversation_id=? AND id<? ORDER BY id DESC LIMIT ?", (chat_id, before_id, page_size)).fetchall()))
        else:
            rows = list(reversed(connection.execute("SELECT * FROM messages WHERE conversation_id=? ORDER BY id DESC LIMIT ?", (chat_id, page_size)).fetchall()))
        total = connection.execute("SELECT COUNT(*) FROM messages WHERE conversation_id=?", (chat_id,)).fetchone()[0]
        if not rows:
            has_more = False
        elif after_id is not None:
            has_more = connection.execute("SELECT 1 FROM messages WHERE conversation_id=? AND id>? LIMIT 1", (chat_id, rows[-1]["id"])).fetchone() is not None
        else:
            has_more = connection.execute("SELECT 1 FROM messages WHERE conversation_id=? AND id<? LIMIT 1", (chat_id, rows[0]["id"])).fetchone() is not None
        return {"items": [message_json(row) for row in rows], "total": total, "page_size": page_size, "has_more": has_more}

    @app.post("/api/chats/{chat_id}/messages", status_code=201)
    def send_message(chat_id: int, body: MessageCreate, connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        chat = conversation(connection, chat_id, user)
        if not are_friends(connection, user["id"], peer_id(chat, user)):
            raise HTTPException(403, "Для отправки сообщений добавьте собеседника в друзья")
        cutoff = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat().replace("+00:00", "Z")
        count = connection.execute("SELECT COUNT(*) FROM messages WHERE sender_id=? AND created_at>?", (user["id"], cutoff)).fetchone()[0]
        if count >= 60:
            raise HTTPException(429, "Слишком много сообщений. Подождите минуту")
        if body.image_url:
            match = re.fullmatch(rf"/api/chats/{chat_id}/images/([a-f0-9]{{40}}\.jpg)", body.image_url)
            if not match or not (photo_root / str(chat_id) / match.group(1)).is_file():
                raise HTTPException(422, "Загрузите фотографию в эту переписку заново")
        cursor = connection.execute(
            "INSERT INTO messages(conversation_id,sender_id,body,image_url,created_at) VALUES(?,?,?,?,?)",
            (chat_id, user["id"], body.body, body.image_url, now()),
        )
        return message_json(connection.execute("SELECT * FROM messages WHERE id=?", (cursor.lastrowid,)).fetchone())

    @app.put("/api/chats/{chat_id}/read")
    def mark_read(chat_id: int, connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        conversation(connection, chat_id, user)
        connection.execute("UPDATE messages SET read_at=? WHERE conversation_id=? AND sender_id<>? AND read_at IS NULL", (now(), chat_id, user["id"]))
        return {"ok": True}

    @app.post("/api/chats/{chat_id}/images", status_code=201)
    async def upload_chat_photo(chat_id: int, file: UploadFile = File(), connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        chat = conversation(connection, chat_id, user)
        if not are_friends(connection, user["id"], peer_id(chat, user)):
            raise HTTPException(403, "Для отправки фотографий добавьте собеседника в друзья")
        content = await file.read(max_upload + 1)
        await file.close()
        if len(content) > max_upload:
            raise HTTPException(413, "Фотография должна быть не больше 8 МБ")
        name = await run_in_threadpool(app.state.image_storage.save, content, photo_root / str(chat_id))
        return {"url": f"/api/chats/{chat_id}/images/{name}"}

    @app.get("/api/chats/{chat_id}/images/{filename}")
    def get_chat_photo(chat_id: int, filename: str, connection: sqlite3.Connection = Depends(db_dependency), user=Depends(user_dependency)):
        conversation(connection, chat_id, user)
        if not re.fullmatch(r"[a-f0-9]{40}\.jpg", filename):
            raise HTTPException(404, "Фотография не найдена")
        path = photo_root / str(chat_id) / filename
        if not path.is_file():
            raise HTTPException(404, "Фотография не найдена")
        return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"})

