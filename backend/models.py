import re
from datetime import datetime
from typing import Annotated, Literal
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


def valid_url(value: str | None, local: bool = False) -> str | None:
    if not value:
        return None
    if local and re.fullmatch(r"/(uploads|demo|media/covers)/[a-zA-Z0-9_.-]+", value):
        return value
    parsed = urlparse(value)
    if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("Укажите полную ссылку, начинающуюся с https://")
    return value


class Register(InputModel):
    email: str = Field(min_length=5, max_length=254)
    password: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(min_length=8, max_length=128)
    name: str = Field(min_length=2, max_length=80)
    faculty: str = Field(default="", max_length=120)
    course: int | None = Field(default=None, ge=1, le=6)

    @field_validator("email")
    @classmethod
    def email_check(cls, value: str) -> str:
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Укажите корректную электронную почту")
        return value.lower()


class Login(InputModel):
    email: str = Field(min_length=1, max_length=254)
    password: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(min_length=1, max_length=128)


class ProfilePatch(InputModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    handle: str | None = Field(default=None, min_length=3, max_length=30)
    avatar_color: str | None = Field(default=None, min_length=7, max_length=7)
    faculty: str | None = Field(default=None, max_length=120)
    course: int | None = Field(default=None, ge=1, le=6)
    bio: str | None = Field(default=None, max_length=500)
    interests: list[str] | None = Field(default=None, max_length=6)
    avatar_url: str | None = Field(default=None, max_length=2048)

    @field_validator("avatar_url")
    @classmethod
    def avatar_url_check(cls, value):
        return valid_url(value, True)

    @field_validator("handle")
    @classmethod
    def handle_check(cls, value):
        if value is not None and not re.fullmatch(r"[A-Za-z0-9_.]{3,30}", value):
            raise ValueError("Используйте от 3 до 30 латинских букв, цифр, точек или подчёркиваний")
        return value.lower() if value is not None else None

    @field_validator("avatar_color")
    @classmethod
    def avatar_color_check(cls, value):
        if value is not None and not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError("Укажите цвет в формате #RRGGBB")
        return value.upper() if value is not None else None


class PostCreate(InputModel):
    type: Literal["news", "event"] = "news"
    title: str = Field(min_length=5, max_length=140)
    body: str = Field(min_length=20, max_length=12000)
    category: str = Field(min_length=1, max_length=40)
    cover_url: str | None = Field(default=None, max_length=2048)
    image_urls: list[Annotated[str, StringConstraints(max_length=2048)]] | None = Field(default=None, max_length=6)
    event_start: datetime | None = None
    event_end: datetime | None = None
    location: str | None = Field(default=None, max_length=200)
    price: str | None = Field(default=None, max_length=80)
    registration_url: str | None = Field(default=None, max_length=2048)
    submit: bool = True

    @field_validator('image_urls')
    @classmethod
    def images_check(cls, value):
        if value is None:
            return None
        if any(not item or not valid_url(item, True) for item in value):
            raise ValueError('Укажите корректные адреса фотографий')
        return list(dict.fromkeys(value))

    @field_validator("cover_url")
    @classmethod
    def cover_url_check(cls, value):
        return valid_url(value, True)

    @field_validator("registration_url")
    @classmethod
    def registration_url_check(cls, value):
        return valid_url(value)


class PostPatch(InputModel):
    type: Literal["news", "event"] | None = None
    title: str | None = Field(default=None, min_length=5, max_length=140)
    body: str | None = Field(default=None, min_length=20, max_length=12000)
    category: str | None = Field(default=None, min_length=1, max_length=40)
    cover_url: str | None = Field(default=None, max_length=2048)
    image_urls: list[Annotated[str, StringConstraints(max_length=2048)]] | None = Field(default=None, max_length=6)
    event_start: datetime | None = None
    event_end: datetime | None = None
    location: str | None = Field(default=None, max_length=200)
    price: str | None = Field(default=None, max_length=80)
    registration_url: str | None = Field(default=None, max_length=2048)
    submit: bool | None = None

    @field_validator('image_urls')
    @classmethod
    def images_check(cls, value):
        if value is None:
            raise ValueError('Список фотографий не может быть null')
        if any(not item or not valid_url(item, True) for item in value):
            raise ValueError('Укажите корректные адреса фотографий')
        return list(dict.fromkeys(value))

    @field_validator("cover_url")
    @classmethod
    def cover_url_check(cls, value):
        return valid_url(value, True)

    @field_validator("registration_url")
    @classmethod
    def registration_url_check(cls, value):
        return valid_url(value)


class Reaction(InputModel):
    reaction: Literal["like", "fire", "heart", "clap"]


class CommentCreate(InputModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: int | None = Field(default=None, ge=1)


class Decision(InputModel):
    decision: Literal["publish", "changes_requested", "reject"]
    expected_updated_at: str = Field(min_length=20, max_length=80)
    reason: str | None = Field(default=None, min_length=3, max_length=1000)


class Report(InputModel):
    reason: str = Field(min_length=3, max_length=500)
