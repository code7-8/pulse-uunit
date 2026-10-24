import sqlite3
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 email TEXT NOT NULL UNIQUE COLLATE NOCASE,
 password_hash TEXT NOT NULL,
 name TEXT NOT NULL,
 handle TEXT NOT NULL UNIQUE,
 faculty TEXT NOT NULL DEFAULT '',
 course INTEGER,
 bio TEXT NOT NULL DEFAULT '',
 avatar_url TEXT,
 avatar_color TEXT NOT NULL DEFAULT '#BAEC7B',
 role TEXT NOT NULL DEFAULT 'student' CHECK(role IN ('student','moderator')),
 interests TEXT NOT NULL DEFAULT '[]',
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
 token_hash TEXT PRIMARY KEY,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL,
 expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS demo_onboarding (
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ai_reviews (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 revision TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'queued',
 reason TEXT NOT NULL DEFAULT '',
 model TEXT NOT NULL DEFAULT '',
 provider TEXT NOT NULL DEFAULT '',
 cost_usd REAL NOT NULL DEFAULT 0,
 images_checked INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL,
 UNIQUE(post_id,revision)
);
CREATE TABLE IF NOT EXISTS auth_attempts (
 id INTEGER PRIMARY KEY,
 address TEXT NOT NULL,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS categories (
 id TEXT PRIMARY KEY,
 name TEXT NOT NULL,
 color TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS posts (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 author_id INTEGER NOT NULL REFERENCES users(id),
 type TEXT NOT NULL CHECK(type IN ('news','event')),
 title TEXT NOT NULL,
 body TEXT NOT NULL,
 category TEXT NOT NULL REFERENCES categories(id),
 cover_url TEXT,
 image_urls TEXT NOT NULL DEFAULT '[]',
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','pending','published','changes_requested','rejected')),
 moderation_reason TEXT,
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL,
 published_at TEXT,
 event_start TEXT,
 event_end TEXT,
 location TEXT,
 price TEXT,
 registration_url TEXT,
 is_demo INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS follows (
 follower_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 following_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 PRIMARY KEY(follower_id, following_id), CHECK(follower_id != following_id)
);
CREATE TABLE IF NOT EXISTS friendships (
 user_low INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 user_high INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 requester_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL,
 accepted_at TEXT,
 PRIMARY KEY(user_low,user_high),
 CHECK(user_low < user_high),
 CHECK(requester_id IN (user_low,user_high))
);
CREATE TABLE IF NOT EXISTS conversations (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 user_low INTEGER NOT NULL REFERENCES users(id),
 user_high INTEGER NOT NULL REFERENCES users(id),
 created_at TEXT NOT NULL,
 UNIQUE(user_low,user_high),
 CHECK(user_low < user_high)
);
CREATE TABLE IF NOT EXISTS messages (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
 sender_id INTEGER NOT NULL REFERENCES users(id),
 body TEXT NOT NULL,
 image_url TEXT,
 created_at TEXT NOT NULL,
 read_at TEXT
);
CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id,id);
CREATE TABLE IF NOT EXISTS bookmarks (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 PRIMARY KEY(user_id, post_id)
);
CREATE TABLE IF NOT EXISTS reactions (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 reaction TEXT NOT NULL CHECK(reaction IN ('like','fire','heart','clap')),
 PRIMARY KEY(user_id, post_id)
);
CREATE TABLE IF NOT EXISTS attendance (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 PRIMARY KEY(user_id, post_id)
);
CREATE TABLE IF NOT EXISTS comments (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 author_id INTEGER NOT NULL REFERENCES users(id),
 body TEXT NOT NULL,
 created_at TEXT NOT NULL,
 parent_id INTEGER REFERENCES comments(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS moderation_history (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 actor_id INTEGER NOT NULL REFERENCES users(id),
 decision TEXT NOT NULL,
 reason TEXT,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS comment_reports (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 comment_id INTEGER NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id),
 reason TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved')),
 created_at TEXT NOT NULL,
 UNIQUE(comment_id, user_id)
);
CREATE TABLE IF NOT EXISTS notifications (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 title TEXT NOT NULL,
 body TEXT NOT NULL,
 post_id INTEGER REFERENCES posts(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL,
 is_read INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS posts_status_published ON posts(status, published_at DESC);
CREATE INDEX IF NOT EXISTS posts_author_status ON posts(author_id, status);
CREATE INDEX IF NOT EXISTS comments_post ON comments(post_id, created_at);
CREATE INDEX IF NOT EXISTS sessions_expires ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS auth_attempts_address ON auth_attempts(address, created_at);
"""


def connect(path: str | Path) -> sqlite3.Connection:
    connection = sqlite3.connect(str(path), timeout=15, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA busy_timeout = 15000")
    return connection


def initialize(path: str | Path) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as connection:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.executescript(SCHEMA)
        message_columns = {row["name"] for row in connection.execute("PRAGMA table_info(messages)")}
        if "image_url" not in message_columns:
            connection.execute("ALTER TABLE messages ADD COLUMN image_url TEXT")
        if 'image_urls' not in {row['name'] for row in connection.execute('PRAGMA table_info(posts)')}:
            connection.execute("ALTER TABLE posts ADD COLUMN image_urls TEXT NOT NULL DEFAULT '[]'")
