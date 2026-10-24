"""Publish only an Ed25519-signed endpoint to a public, anonymous JSON record."""
from __future__ import annotations

import json
from pathlib import Path
import re
import httpx

from backend.identity import ServerIdentity

STORE = "https://superjsonblob.com/api/jsonBlob"


def json_request(method, url, value=None):
    with httpx.Client(trust_env=False, timeout=10, follow_redirects=False) as client:
        response = client.request(method, url, json=value, headers={
            "Accept": "application/json", "Cache-Control": "no-cache"})
        response.raise_for_status()
        if len(response.content) > 16384:
            raise ValueError("Oversized directory response")
        return response.json()


def prepare(directory: Path):
    identity = ServerIdentity.prepare(directory)
    path = directory / "discovery.json"
    if path.exists():
        config = json.loads(path.read_text(encoding="utf-8"))
        if config["instance"] != identity.instance or config["public_key"] != identity.public_key:
            raise ValueError("Discovery identity mismatch; keep the original key and instance")
        return identity, config
    created = json_request("POST", STORE, {"status": "starting", "service": "pulse"})
    identifier = created["id"]
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9-]{8,100}", identifier):
        raise ValueError("Invalid record identifier")
    config = {"url": STORE + "/" + identifier, "instance": identity.instance, "public_key": identity.public_key}
    path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return identity, config


def publish(identity, config, endpoint, valid_until):
    envelope = identity.envelope(endpoint, valid_until)
    json_request("PUT", config["url"], envelope)
    if json_request("GET", config["url"]) != envelope:
        raise ValueError("Discovery read-back failed")
    return envelope
