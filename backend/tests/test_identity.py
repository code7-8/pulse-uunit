import base64
import json
import pytest
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi.testclient import TestClient
from backend.identity import ServerIdentity
from backend.main import create_app


def test_identity_survives_restart_and_detects_modified_endpoint(tmp_path):
    identity = ServerIdentity.prepare(tmp_path)
    second = ServerIdentity.prepare(tmp_path)
    assert identity.instance == second.instance
    assert identity.public_key == second.public_key
    record = identity.envelope("https://test.lhr.life", "2026-10-27T00:00:00+05:00")
    payload = base64.b64decode(record["payload"])
    signature = base64.b64decode(record["signature"])
    public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(identity.public_key))
    public_key.verify(signature, payload)
    with pytest.raises(InvalidSignature):
        public_key.verify(signature, payload.replace(b"test.lhr.life", b"evil.lhr.life"))
    assert b"PRIVATE" not in json.dumps(record).encode()


def test_live_proof_is_bound_to_nonce_and_current_public_origin(tmp_path, monkeypatch):
    identity = ServerIdentity.prepare(tmp_path / "identity")
    endpoint = tmp_path / "status.json"
    endpoint.write_text(json.dumps({"url": "https://first.lhr.life"}))
    monkeypatch.setenv("PULSE_IDENTITY_KEY", str(tmp_path / "identity" / "identity.pem"))
    monkeypatch.setenv("PULSE_INSTANCE_ID", identity.instance)
    monkeypatch.setenv("PULSE_ENDPOINT_STATE", str(endpoint))
    app = create_app(tmp_path / "db.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads")
    public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(identity.public_key))
    nonce = "abc_123-" * 5
    with TestClient(app) as client:
        proof = client.get("/api/server-proof", params={"nonce": nonce}).json()
        signature = base64.b64decode(proof["signature"])
        message = f"pulse-server-proof:v1:{identity.instance}:https://first.lhr.life:{nonce}".encode()
        public_key.verify(signature, message)
        with pytest.raises(InvalidSignature):
            public_key.verify(signature, message + b"replayed")
        endpoint.write_text(json.dumps({"url": "https://second.lhr.life"}))
        assert client.get("/api/server-proof", params={"nonce": nonce}).json()["url"] == "https://second.lhr.life"
        assert client.get("/api/server-proof?nonce=short").status_code == 422
        endpoint.write_text(json.dumps({"url": None}))
        assert client.get("/api/server-proof", params={"nonce": nonce}).status_code == 503


def test_unconfigured_local_server_does_not_offer_an_identity(tmp_path, monkeypatch):
    monkeypatch.delenv("PULSE_IDENTITY_KEY", raising=False)
    with TestClient(create_app(tmp_path / "db.sqlite3", seed_demo=False, upload_dir=tmp_path / "uploads")) as client:
        assert client.get("/api/server-proof?nonce=" + "a" * 32).status_code == 404
