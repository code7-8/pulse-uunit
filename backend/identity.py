"""Signed discovery data. The private key never leaves the laptop."""
from __future__ import annotations

import base64
import json
from pathlib import Path
import secrets

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class ServerIdentity:
    def __init__(self, key_path: Path, instance: str):
        self.key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        if not isinstance(self.key, Ed25519PrivateKey):
            raise ValueError("Expected an Ed25519 identity")
        self.instance = instance

    @classmethod
    def prepare(cls, directory: Path):
        directory.mkdir(parents=True, exist_ok=True)
        key_path = directory / "identity.pem"
        instance_path = directory / "instance.txt"
        if not key_path.exists():
            key = Ed25519PrivateKey.generate()
            with key_path.open("xb") as target:
                target.write(key.private_bytes(serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            if __import__("os").name != "nt":
                key_path.chmod(0o600)
        if not instance_path.exists():
            instance_path.write_text(secrets.token_urlsafe(18), encoding="utf-8")
        return cls(key_path, instance_path.read_text(encoding="utf-8").strip())

    @property
    def public_key(self):
        return base64.b64encode(self.key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode("ascii")

    def sign(self, data: bytes):
        return base64.b64encode(self.key.sign(data)).decode("ascii")

    def envelope(self, url: str, valid_until: str):
        payload = json.dumps({"service": "pulse", "version": 1, "instance": self.instance,
            "url": url, "valid_until": valid_until}, separators=(",", ":")).encode("utf-8")
        return {"payload": base64.b64encode(payload).decode("ascii"), "signature": self.sign(payload)}

    def proof(self, nonce: str, url: str):
        data = f"pulse-server-proof:v1:{self.instance}:{url}:{nonce}".encode("utf-8")
        return {"instance": self.instance, "url": url, "nonce": nonce, "signature": self.sign(data)}
