"""Bounded, re-encoded image storage, shared by covers and private chats."""
from __future__ import annotations

import io
import secrets
import shutil
import threading
from pathlib import Path

from fastapi import HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError


class ImageStorage:
    def __init__(self, roots: list[Path], quota_bytes: int = 1024 * 1024 * 1024,
                 minimum_free_bytes: int = 1024 * 1024 * 1024):
        self.roots = [root.resolve() for root in roots]
        self.quota_bytes, self.minimum_free_bytes = quota_bytes, minimum_free_bytes
        self.lock = threading.Lock()
        self.processing = threading.BoundedSemaphore(2)
        for root in self.roots:
            root.mkdir(parents=True, exist_ok=True)

    def save(self, content: bytes, folder: Path) -> str:
        folder = folder.resolve()
        if not any(folder == root or root in folder.parents for root in self.roots):
            raise ValueError("Image folder is outside configured storage")
        if not self.processing.acquire(blocking=False):
            raise HTTPException(503, "Обрабатываются другие фотографии. Повторите загрузку", headers={"Retry-After": "5"})
        try:
            if len(content) > 8 * 1024 * 1024:
                raise HTTPException(413, "Фотография должна быть не больше 8 МБ")
            try:
                with Image.open(io.BytesIO(content)) as source:
                    if source.format not in ("JPEG", "PNG", "WEBP"):
                        raise HTTPException(422, "Выберите фотографию JPEG, PNG или WebP")
                    if source.width * source.height > 30_000_000:
                        raise HTTPException(422, "Слишком большое разрешение фотографии")
                    source.verify()
                with Image.open(io.BytesIO(content)) as source:
                    image = ImageOps.exif_transpose(source).convert("RGB")
                    image.thumbnail((2400, 2400))
                    buffer = io.BytesIO()
                    image.save(buffer, "JPEG", quality=90, optimize=True)
                    output = buffer.getvalue()
            except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
                raise HTTPException(422, "Не удалось открыть фотографию")
            with self.lock:
                used = sum(p.stat().st_size for root in self.roots for p in root.rglob("*") if p.is_file())
                if used + len(output) > self.quota_bytes:
                    raise HTTPException(507, "Хранилище фотографий заполнено. Сообщите организатору")
                if shutil.disk_usage(self.roots[0]).free - len(output) < self.minimum_free_bytes:
                    raise HTTPException(507, "На сервере недостаточно свободного места")
                folder.mkdir(parents=True, exist_ok=True)
                name = secrets.token_hex(20) + ".jpg"
                # Exclusive creation prevents replacement of an existing file.
                with (folder / name).open("xb") as destination:
                    destination.write(output)
                return name
        finally:
            self.processing.release()
