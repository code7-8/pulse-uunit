"""Optional hackathon onboarding. Adds fictional contacts, never other real users."""
from pathlib import Path
import json
from fastapi import HTTPException
from .seed import stamp
from datetime import datetime, timedelta, timezone

DEMO_BIO = "Демонстрационный профиль для показа приложения."
FRIENDS = (
    ("timur@pulse.local", "Привет! На вечер кода можно прийти без опыта разработки. Если соберёшься, отметь участие в событии."),
    ("artem@pulse.local", "Привет! На открытую тренировку можно прийти без команды. Напиши, если понадобятся подробности."),
)
DISCUSSIONS = {
    "Кампус в объективе: подборка студенческих фотографий": ("Первый кадр очень тёплый. Осенью кампус особенно красивый.", "Спасибо! Если есть свои фотографии, присылай отдельную публикацию — соберём следующую подборку."),
    "Что помогает освоиться на первом курсе": ("Ещё советую заранее находить аудитории, если занятия в незнакомом корпусе.", "Да, спасибо. В первые дни сам тратил на это много времени. Добавлю совет в список."),
    "Научный кофе: как начать своё исследование": ("Можно прийти, если пока нет своей темы?", "Да. Разберём несколько примеров и поможем выбрать небольшой исследовательский вопрос."),
    "Как собрать портфолио, если опыта работы ещё нет": ("Учебный командный проект тоже подойдёт?", "Да, только отдельно опиши свой вклад. Скриншоты и ссылка на результат тоже пригодятся."),
    "Обмен вещами: дайте книгам вторую жизнь": ("Есть два учебника по математике. Можно принести оба?", "Конечно. Если внутри есть пометки, просто предупреди следующего владельца."),
    "Лёгкая пробежка перед занятиями": ("Какой примерно будет темп? Давно не бегала.", "Ориентируемся на спокойный разговорный темп. При необходимости часть маршрута пройдём пешком."),
    "Разбор резюме: первая стажировка": ("Резюме обязательно приносить распечатанным?", "Нет, можно открыть на ноутбуке или телефоне. Главное — чтобы тебе было удобно вносить правки."),
    "Фотопрогулка по осенней Уфе": ("С телефоном можно присоединиться?", "Да, подойдёт любая камера. Больше внимания уделим свету и композиции."),
    "Мини-исследование: сколько одноразовых стаканов мы используем": ("Могу помочь с диаграммами и обработкой результатов.", "Отлично. Сначала согласуем вопросы анкеты, чтобы данные потом можно было сравнить."),
    "Ищем напарников для регулярных тренировок": ("Мне удобнее по вторникам и четвергам после 17:00.", "Записал. Соберём варианты времени и выберем те, которые подойдут большинству."),
    "Свободный стол для совместной учёбы": ("Готовлюсь по алгоритмам, могу присоединиться вечером.", "Подойдёт. Принеси свои задачи — в перерыве сможем разобрать сложные места вместе."),
}


def onboard_user(connection, user_id, *, storage=None, photo_root=None, cover=None):
    if connection.execute("SELECT 1 FROM demo_onboarding WHERE user_id=?", (user_id,)).fetchone():
        return False
    peers = {row["email"]: row for row in connection.execute(
        "SELECT * FROM users WHERE email IN ('timur@pulse.local','artem@pulse.local','daria@pulse.local')")}
    if len(peers) != 3:
        return False
    current = datetime.now(timezone.utc)
    created = stamp(current - timedelta(minutes=12))
    for index, (email, text) in enumerate(FRIENDS):
        peer = peers[email]
        if peer["id"] == user_id:
            continue
        low, high = sorted((peer["id"], user_id))
        connection.execute("INSERT INTO friendships(user_low,user_high,requester_id,created_at,accepted_at) VALUES(?,?,?,?,?) ON CONFLICT(user_low,user_high) DO UPDATE SET accepted_at=COALESCE(friendships.accepted_at,excluded.accepted_at)",
            (low, high, peer["id"], created, created))
        connection.execute("INSERT OR IGNORE INTO follows(follower_id,following_id) VALUES(?,?)", (user_id, peer["id"]))
        connection.execute("INSERT OR IGNORE INTO conversations(user_low,user_high,created_at) VALUES(?,?,?)", (low, high, created))
        chat = connection.execute("SELECT id FROM conversations WHERE user_low=? AND user_high=?", (low, high)).fetchone()[0]
        if connection.execute("SELECT 1 FROM messages WHERE conversation_id=?", (chat,)).fetchone():
            continue
        connection.execute("INSERT INTO messages(conversation_id,sender_id,body,created_at) VALUES(?,?,?,?)", (chat, peer["id"], text, created))
        if index == 0 and storage and photo_root and cover and Path(cover).is_file():
            try:
                filename = storage.save(Path(cover).read_bytes(), Path(photo_root) / str(chat))
            except (OSError, HTTPException):
                # Registration still works when the photo quota is exhausted.
                continue
            connection.execute("INSERT INTO messages(conversation_id,sender_id,body,image_url,created_at) VALUES(?,?,?,?,?)",
                (chat, peer["id"], "Фотография с прошлой встречи.", f"/api/chats/{chat}/images/{filename}", stamp(current - timedelta(minutes=5))))
    peer = peers["daria@pulse.local"]
    if peer["id"] != user_id:
        low, high = sorted((peer["id"], user_id))
        result = connection.execute("INSERT OR IGNORE INTO friendships(user_low,user_high,requester_id,created_at) VALUES(?,?,?,?)", (low, high, peer["id"], stamp(current)))
        if result.rowcount:
            connection.execute("INSERT INTO notifications(user_id,title,body,created_at) VALUES(?,?,?,?)",
                (user_id, "Заявка в друзья", f"{peer['name']} хочет добавить вас в друзья", stamp(current)))
    connection.execute("INSERT INTO demo_onboarding(user_id,created_at) VALUES(?,?)", (user_id, stamp(current)))
    return True


def prepare_review_users(connection, **media):
    galleries = {
        'Вечер кода: от идеи до первого приложения': ['coding', 'campus', 'community'],
        'Научный кофе: как начать своё исследование': ['science', 'coding'],
        'Открытая тренировка по баскетболу': ['sport', 'campus'],
        'Фотопрогулка по осенней Уфе': ['culture', 'campus', 'community'],
    }
    for title, pictures in galleries.items():
        connection.execute("UPDATE posts SET image_urls=? WHERE is_demo=1 AND title=? AND image_urls='[]'",
            (json.dumps(['/media/covers/' + name + '.jpg' for name in pictures]), title))
    for row in connection.execute("SELECT id,bio FROM users WHERE email LIKE '%@pulse.local'").fetchall():
        if DEMO_BIO not in row["bio"]:
            connection.execute("UPDATE users SET bio=? WHERE id=?", ((row["bio"] + "\n\n" + DEMO_BIO).strip(), row["id"]))
    commenters = connection.execute("SELECT id FROM users WHERE email IN ('alina@pulse.local','sofia@pulse.local','ruslan@pulse.local') ORDER BY id").fetchall()
    if commenters:
        for index, (title, (question, answer)) in enumerate(DISCUSSIONS.items()):
            post = connection.execute("SELECT id,author_id FROM posts WHERE is_demo=1 AND status='published' AND title=?", (title,)).fetchone()
            if not post:
                continue
            existing = connection.execute("SELECT id FROM comments WHERE post_id=? ORDER BY id", (post["id"],)).fetchall()
            if len(existing) >= 2:
                continue
            author = commenters[index % len(commenters)]["id"]
            if author == post["author_id"]:
                author = commenters[(index + 1) % len(commenters)]["id"]
            created = datetime.now(timezone.utc) - timedelta(minutes=40 + index * 2)
            root = existing[0]["id"] if existing else connection.execute("INSERT INTO comments(post_id,author_id,body,created_at) VALUES(?,?,?,?)", (post["id"], author, question, stamp(created))).lastrowid
            connection.execute("INSERT INTO comments(post_id,author_id,body,parent_id,created_at) VALUES(?,?,?,?,?)", (post["id"], post["author_id"], answer, root, stamp(created + timedelta(minutes=7))))
    for user in connection.execute("SELECT id FROM users WHERE email NOT LIKE '%@pulse.local' OR email='student@pulse.local'").fetchall():
        onboard_user(connection, user["id"], **media)
