"""Project-local supervisor for the temporary public hackathon server."""
from __future__ import annotations

import argparse
import ctypes
import json
import ipaddress
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener

WORKSPACE = Path(__file__).resolve().parents[1]
ROOT = WORKSPACE / "runtime" / "server"
sys.path.insert(0, str(WORKSPACE))
from backend.database import connect, initialize
from backend.security import hash_password, verify_password
from backend.seed import seed
from scripts.endpoint_discovery import prepare as prepare_discovery, publish as publish_discovery

CREATE_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
URL_PATTERN = re.compile(r"https://[a-z0-9-]+\.(?:trycloudflare\.com|lhr\.life|ngrok-free\.app|ngrok-free\.dev|ngrok\.app)\b")


def save_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    for attempt in range(10):
        try:
            temporary.replace(path)
            return
        except PermissionError:
            if attempt == 9:
                raise
            time.sleep(0.05)


def prepare():
    for folder in (ROOT, ROOT / "logs", ROOT / "tmp", ROOT / "backups", ROOT / "data"):
        folder.mkdir(parents=True, exist_ok=True)
    # Child processes inherit this project-local temporary directory.
    os.environ["TEMP"] = os.environ["TMP"] = str(ROOT / "tmp")
    config_path = ROOT / "settings.json"
    if not config_path.exists():
        save_json(config_path, {"port": 8000, "media_quota_mb": 1024, "provider": "localhost.run",
            "end_at": "2026-10-27T00:00:00+05:00", "backup_interval_minutes": 60})
    database = ROOT / "data" / "pulse.sqlite3"
    if not database.exists():
        original = WORKSPACE / "backend" / "data" / "pulse.sqlite3"
        if original.exists():
            with sqlite3.connect(f"file:{original.as_posix()}?mode=ro", uri=True) as source, sqlite3.connect(database) as target:
                source.backup(target)
            for name in ("uploads", "chat_uploads"):
                source_folder = original.parent / name
                if source_folder.is_dir():
                    shutil.copytree(source_folder, ROOT / "data" / name, dirs_exist_ok=True)
        initialize(database)
        with connect(database) as connection:
            seed(connection, include_demo=True)
    credentials = ROOT / "ДОСТУПЫ.txt"
    # Only rotate shared seed credentials. Existing real registrations survive.
    lines = []
    with connect(database) as connection:
        rows = connection.execute("SELECT id,email,password_hash,role FROM users WHERE email LIKE '%@pulse.local'").fetchall()
        for row in rows:
            if verify_password("Student123!", row["password_hash"]) or verify_password("Moderator123!", row["password_hash"]):
                password = secrets.token_urlsafe(18)
                connection.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(password), row["id"]))
                connection.execute("DELETE FROM sessions WHERE user_id=?", (row["id"],))
                lines.append(f"{row['email']}\nРоль: {row['role']}\nПароль: {password}\n")
        # Old local media addresses must not leak into the public deployment.
        for table, field in (("posts", "cover_url"), ("users", "avatar_url")):
            for row in connection.execute(f"SELECT id,{field} FROM {table} WHERE {field} LIKE 'http://192.168.%'"):
                value = urlsplit(row[field])
                if value.path.startswith(("/uploads/", "/media/")):
                    connection.execute(f"UPDATE {table} SET {field}=? WHERE id=?", (value.path, row["id"]))
    if lines:
        previous = credentials.read_text(encoding="utf-8") if credentials.exists() else "Доступ к публичному серверу Пульс. Не отправляйте этот файл команде.\n\n"
        credentials.write_text(previous + "\n".join(lines), encoding="utf-8")
        if os.name != "nt":
            credentials.chmod(0o600)
    return json.loads(config_path.read_text(encoding="utf-8"))


def backup():
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    destination = ROOT / "backups" / f"pulse-{stamp}.sqlite3"
    with sqlite3.connect(ROOT / "data" / "pulse.sqlite3") as source, sqlite3.connect(destination) as target:
        source.backup(target)
    # Delete only our exact, verified backup filenames inside this directory.
    for old in sorted((ROOT / "backups").glob("pulse-????????-??????.sqlite3"), reverse=True)[24:]:
        if old.resolve().parent == (ROOT / "backups").resolve():
            old.unlink()


def run():
    ROOT.mkdir(parents=True, exist_ok=True)
    lock = (ROOT / "server.lock").open("a+b")
    if os.name == "nt":
        import msvcrt
        lock.seek(0)
        if not lock.read(1):
            lock.write(b"1")
            lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit("Сервер уже запущен")
    config = prepare()
    server_identity, discovery = prepare_discovery(ROOT)
    end_at = datetime.fromisoformat(config["end_at"])
    if datetime.now().astimezone() >= end_at:
        raise SystemExit("Срок публичного стенда закончился. При необходимости измените end_at в runtime/server/settings.json")
    (ROOT / "stop.request").unlink(missing_ok=True)
    handler = RotatingFileHandler(ROOT / "logs" / "server.log", maxBytes=2 * 1024 * 1024, backupCount=3, encoding="utf-8")
    logging.basicConfig(level=logging.INFO, handlers=[handler], format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("pulse")
    tunnel_binary = WORKSPACE / ".tools" / "tunnel" / "cloudflared.exe"
    provider = config.get("provider", "localhost.run")
    if provider == "cloudflare" and not tunnel_binary.is_file():
        raise SystemExit("Не найден .tools/tunnel/cloudflared.exe")
    port = int(config["port"])
    with socket.socket() as probe:
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            raise SystemExit(f"Порт {port} уже занят. Остановите прежний сервер")
    child_env = os.environ.copy()
    child_env.update(PULSE_PUBLIC_MODE="true", PULSE_TRUST_PROXY="cloudflare" if provider == "cloudflare" else "none", PULSE_SEED_DEMO="false",
        PULSE_DB=str(ROOT / "data" / "pulse.sqlite3"), PULSE_UPLOAD_DIR=str(ROOT / "data" / "uploads"),
        PULSE_MEDIA_QUOTA_MB=str(config["media_quota_mb"]), PULSE_CORS_ORIGINS="", PYTHONUNBUFFERED="1", PYTHONUTF8="1")
    child_env.update(PULSE_IDENTITY_KEY=str(ROOT / "identity.pem"), PULSE_INSTANCE_ID=server_identity.instance,
                     PULSE_ENDPOINT_STATE=str(ROOT / "status.json"), PULSE_REVIEW_DEMO=str(config.get("review_demo", True)).lower())
    child_env.update(PULSE_AI_ENABLED='true', PULSE_OPENROUTER_KEY_FILE=str(ROOT / 'openrouter.key'), PULSE_AI_BUDGET_USD=str(config.get('ai_budget_usd', 1.60)))
    children = {}
    launched_at = {}
    state = {"pid": os.getpid(), "url": None, "local_url": f"http://127.0.0.1:{port}",
             "started_at": datetime.now().astimezone().isoformat(), "end_at": config["end_at"]}
    state_lock = threading.Lock()
    opener = build_opener(ProxyHandler({}))
    publisher_stop = threading.Event()

    def publisher():
        last_published = None
        while not publisher_stop.wait(3):
            with state_lock:
                endpoint = state["url"]
            if not endpoint or endpoint == last_published:
                continue
            try:
                envelope = publish_discovery(server_identity, discovery, endpoint, config["end_at"])
                save_json(ROOT / "endpoint.json", envelope)
                last_published = endpoint
                log.info("Published signed endpoint: %s", endpoint)
            except Exception:
                log.warning("Endpoint publication failed; will retry", exc_info=True)
                publisher_stop.wait(12)

    def launch(name, args):
        process = subprocess.Popen(args, cwd=WORKSPACE, env=child_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   creationflags=CREATE_FLAGS, text=True, encoding="utf-8", errors="replace", bufsize=1)
        children[name] = process
        launched_at[name] = time.monotonic()

        def output():
            for line in process.stdout:
                log.info("%s: %s", name, line.rstrip())
                if name == "tunnel":
                    found = URL_PATTERN.search(line)
                    if found:
                        with state_lock:
                            state["url"] = found.group()
                        (ROOT / "АДРЕС_СЕРВЕРА.txt").write_text(found.group() + "\n", encoding="utf-8")
        threading.Thread(target=output, daemon=True).start()
        log.info("Started %s pid=%s", name, process.pid)

    backend_command = [sys.executable, "-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", str(port),
        "--no-proxy-headers", "--no-server-header", "--no-access-log", "--timeout-keep-alive", "5",
        "--limit-concurrency", "32", "--backlog", "64"]
    tunnel_command = [str(tunnel_binary), "tunnel", "--no-autoupdate", "--no-prechecks", "--protocol", "http2",
        "--url", state["local_url"], "--metrics", "127.0.0.1:20241", "--loglevel", "info"]
    # Some VPN DNS resolvers do not support SRV queries used by Go. Resolve
    # Cloudflare's published edge A records via HTTPS for this process only.
    # This does not modify Windows DNS, the hosts file, or VPN settings.
    for region in (("region1.v2.argotunnel.com", "region2.v2.argotunnel.com") if provider == "cloudflare" else ()):
        try:
            with opener.open("https://dns.google/resolve?name=" + region + "&type=A", timeout=8) as response:
                answers = json.load(response).get("Answer", [])
            addresses = [str(ipaddress.ip_address(a["data"])) for a in answers if a.get("type") == 1]
            for address in addresses[:2]:
                tunnel_command.extend(["--edge", address + ":7844"])
        except (URLError, ValueError, OSError):
            log.warning("Could not resolve %s via HTTPS; using connector discovery", region)
    if provider == "localhost.run":
        ssh = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32" / "OpenSSH" / "ssh.exe"
        keygen = ssh.with_name("ssh-keygen.exe")
        identity = ROOT / "tunnel_key"
        if not identity.exists():
            subprocess.run([str(keygen), "-q", "-t", "ed25519", "-N", "", "-C", "pulse-hackathon-tunnel",
                            "-f", str(identity)], check=True, creationflags=CREATE_FLAGS)
        tunnel_command = [str(ssh), "-F", "NUL", "-T", "-i", str(identity), "-o", "IdentitiesOnly=yes",
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=" + str(ROOT / "known_hosts"),
            "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=12", "-R", f"80:127.0.0.1:{port}", "nokey@localhost.run"]
    elif provider == "ngrok":
        ngrok = WORKSPACE / ".tools" / "ngrok" / "ngrok.exe"
        ngrok_config = ROOT / "ngrok.yml"
        if not ngrok.is_file() or not ngrok_config.is_file():
            raise RuntimeError("Run the local ngrok connection helper first")
        tunnel_command = [str(ngrok), "http", state["local_url"], "--config", str(ngrok_config),
                          "--log", "stdout", "--log-format", "json", "--log-level", "info", "--inspect=false"]
    last_backup, restarts = 0, {"backend": 0, "tunnel": 0}
    if os.name == "nt":
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
    try:
        launch("backend", backend_command)
        # Do not publish a service until the guarded backend has started.
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if children["backend"].poll() is not None:
                raise RuntimeError("Backend startup failed; see runtime/server/logs/server.log")
            try:
                with opener.open(state["local_url"] + "/api/health", timeout=2) as response:
                    if json.load(response).get("public") is True:
                        break
            except (URLError, OSError):
                pass
            time.sleep(0.5)
        else:
            raise RuntimeError("Backend startup timed out")
        launch("tunnel", tunnel_command)
        threading.Thread(target=publisher, daemon=True).start()
        while not (ROOT / "stop.request").exists() and datetime.now().astimezone() < end_at:
            for name, command in (("backend", backend_command), ("tunnel", tunnel_command)):
                if children[name].poll() is None and time.monotonic() - launched_at[name] > 300:
                    restarts[name] = 0
                if children[name].poll() is not None:
                    restarts[name] += 1
                    log.warning("%s exited; restarting (%s)", name, restarts[name])
                    if name == "tunnel":
                        with state_lock:
                            state["url"] = None
                    if restarts[name] > 30:
                        raise RuntimeError(f"{name} has failed repeatedly; stopping public access")
                    time.sleep(min(restarts[name] * 2, 30))
                    launch(name, command)
            if time.monotonic() - last_backup > int(config["backup_interval_minutes"]) * 60:
                try:
                    backup()
                    last_backup = time.monotonic()
                except (OSError, sqlite3.Error):
                    log.exception("Database backup failed")
            with state_lock:
                state.update(heartbeat=datetime.now().astimezone().isoformat(), backend_pid=children["backend"].pid,
                             tunnel_pid=children["tunnel"].pid, running=True)
                try:
                    save_json(ROOT / "status.json", state)
                except OSError:
                    log.warning("Could not update status file; the server continues running")
            time.sleep(2)
    except Exception:
        log.exception("Public server stopped after an error")
        raise
    finally:
        publisher_stop.set()
        for process in reversed(list(children.values())):
            if process.poll() is None:
                if os.name == "nt":
                    # The Windows venv launcher can have an interpreter child.
                    # Stop the owned process tree, not just the launcher.
                    subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=CREATE_FLAGS)
                else:
                    process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
        if os.name == "nt":
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        state.update(running=False, stopped_at=datetime.now().astimezone().isoformat())
        save_json(ROOT / "status.json", state)
        lock.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "run", "stop", "status"))
    action = parser.parse_args().action
    if action == "prepare":
        prepare()
        print("Подготовлено: runtime/server. Пароли находятся в runtime/server/ДОСТУПЫ.txt")
    elif action == "stop":
        ROOT.mkdir(parents=True, exist_ok=True)
        (ROOT / "stop.request").touch()
        print("Отправлена команда остановки сервера и туннеля")
    elif action == "status":
        path = ROOT / "status.json"
        print(path.read_text(encoding="utf-8") if path.exists() else "Сервер ещё не запускался")
    else:
        run()
