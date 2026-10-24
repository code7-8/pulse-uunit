"""Fictional demo data. Never represents announcements by the university."""
import json
from datetime import datetime, timedelta, timezone

from .security import hash_password

CATEGORIES = [
    ("campus", "Кампус", "#B8EB7C"),
    ("science", "Наука", "#B7B9FF"),
    ("career", "Карьера", "#FFC28F"),
    ("sport", "Спорт", "#91C9FF"),
    ("culture", "Культура", "#F7A3CD"),
    ("community", "Сообщество", "#B4D8CD"),
]


def stamp(value):
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def seed(connection, include_demo=True):
    connection.executemany("INSERT OR IGNORE INTO categories(id,name,color) VALUES(?,?,?)", CATEGORIES)
    if not include_demo or connection.execute("SELECT 1 FROM users LIMIT 1").fetchone():
        return
    local = datetime.now(timezone(timedelta(hours=5)))
    day = local.replace(hour=0, minute=0, second=0, microsecond=0)
    created = stamp(local - timedelta(days=14))
    accounts = [
        ("student@pulse.local", "Student123!", "Александр Соколов", "alex_sokolov", "Институт информатики, математики и робототехники", 2, "Учусь писать код. Ищу команду на хакатоны и людей для вечерних пробежек.", "student", "#C0EA89", ["science", "career", "sport"]),
        ("moderator@pulse.local", "Moderator123!", "Мария Волкова", "maria_volkova", "Студенческая редакция", 3, "Помогаю авторам выпускать понятные и полезные новости кампуса.", "moderator", "#C7BEF8", ["campus", "community"]),
        ("alina@pulse.local", "Student123!", "Алина Каримова", "alina_karimova", "Институт гуманитарных и социальных наук", 3, "Студенческие проекты, фотография и городские прогулки.", "student", "#F2BDD2", ["culture", "community", "campus"]),
        ("timur@pulse.local", "Student123!", "Тимур Хасанов", "timur_khasanov", "Институт информатики, математики и робототехники", 4, "Разрабатываю приложения и провожу встречи для тех, кто только начинает.", "student", "#B7D4FF", ["science", "career"]),
        ("daria@pulse.local", "Student123!", "Дарья Лебедева", "daria_lebedeva", "Институт природы и человека", 2, "Волонтёрство и маленькие изменения вокруг нас.", "student", "#A9DED0", ["science", "community"]),
        ("artem@pulse.local", "Student123!", "Артём Исламов", "artem_islamov", "Институт электротехнического инжиниринга", 3, "Баскетбол, бег и инженерные проекты.", "student", "#F7D599", ["sport", "campus"]),
        ("sofia@pulse.local", "Student123!", "Софья Морозова", "sofia_morozova", "Институт экономики, управления и бизнеса", 2, "Организую встречи, где можно познакомиться и попробовать новое.", "student", "#D6C6F8", ["career", "culture"]),
        ("ruslan@pulse.local", "Student123!", "Руслан Ахметов", "ruslan_akhmetov", "Институт информатики, математики и робототехники", 1, "Первый курс. Собираю полезные места и знакомства в университете.", "student", "#C3E3A4", ["campus", "community"]),
    ]
    # Reuse a strong salted hash only for accounts sharing the explicitly public demo password.
    student_hash = hash_password("Student123!")
    moderator_hash = hash_password("Moderator123!")
    for email, password, name, handle, faculty, course, bio, role, color, interests in accounts:
        connection.execute("INSERT INTO users(email,password_hash,name,handle,faculty,course,bio,role,avatar_color,interests,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)", (email, moderator_hash if role == "moderator" else student_hash, name, handle, faculty, course, bio, role, color, json.dumps(interests), created))

    # (author, kind, title, category, cover, day offset, hour, location, price, body)
    samples = [
        (4, "event", "Вечер кода: от идеи до первого приложения", "career", "coding", 0, 18, "Коворкинг · корпус на ул. Заки Валиди", "Бесплатно", "Собираемся небольшой группой, чтобы пройти путь от простой идеи до работающего экрана приложения. Начнём с короткого знакомства, обсудим инструменты и разделимся на пары.\n\nМожно прийти без опыта разработки. Возьмите ноутбук и зарядку. Участники с опытом смогут помочь новичкам и найти будущих напарников. В конце покажем друг другу, что получилось, и разберём вопросы."),
        (3, "news", "Кампус в объективе: подборка студенческих фотографий", "campus", "campus", None, None, None, None, "Осенний свет, знакомые лестницы и короткая пауза между парами. Собрали фотографии повседневной жизни кампуса, которые прислали студенты.\n\nХотим продолжить эту серию. Если у вас есть кадр, который передаёт ваше настроение в университете, подготовьте публикацию с фотографией и небольшой историей. Обязательно укажите автора и место съёмки."),
        (6, "event", "Открытая тренировка по баскетболу", "sport", "sport", 1, 17, "Спортивный зал · место уточним участникам", "Бесплатно", "Приглашаем на открытую тренировку: разомнёмся, потренируем броски и сыграем несколько коротких матчей. Можно прийти одному или с друзьями.\n\nОпыт не важен — разделим команды так, чтобы всем было комфортно. Нужны сменная спортивная обувь, форма и вода. Отметьте участие в приложении: так мы поймём, сколько команд собрать."),
        (5, "event", "Научный кофе: как начать своё исследование", "science", "science", 1, 15, "Студенческий коворкинг", "Бесплатно", "Неформальная встреча для тех, кто хочет попробовать себя в исследовании, но пока не знает, с чего начать. Обсудим, как выбрать небольшой вопрос, найти литературу и не потеряться в первых результатах.\n\nПринесите свою идею или просто приходите послушать. После вводной части останется время на вопросы и знакомство с другими участниками."),
        (3, "event", "Киноклуб: смотрим и обсуждаем вместе", "culture", "culture", 2, 18, "Медиазал · студенческое пространство", "Бесплатно", "Воскресный вечер для хорошего кино и разговора после титров. Вместо длинной лекции — короткое вступление и свободное обсуждение.\n\nФильм выберем вместе в комментариях к публикации. Предлагайте варианты продолжительностью до двух часов. Можно прийти только на просмотр или остаться на беседу — участие в обсуждении добровольное."),
        (7, "news", "Как собрать портфолио, если опыта работы ещё нет", "career", "coding", None, None, None, None, "В портфолио могут войти учебный проект, небольшое исследование, дизайн для студенческого сообщества или приложение с хакатона. Главное — объяснить задачу, вашу роль и получившийся результат.\n\nДля начала выберите две работы и опишите каждую на одной странице: что было нужно сделать, какие решения вы приняли, что проверили и чему научились. Если работали в команде, отдельно обозначьте свой вклад. Ссылки на работающий результат и понятные скриншоты помогут читателю быстрее разобраться."),
        (5, "event", "Обмен вещами: дайте книгам вторую жизнь", "community", "community", 3, 12, "Холл студенческого пространства", "Бесплатно", "Книги, блокноты и небольшие полезные вещи можно обменять на встрече сообщества. Приносите только то, чем сами были бы рады пользоваться: чистое и в хорошем состоянии.\n\nПокупать или продавать ничего не нужно. Не обязательно приносить вещь, чтобы забрать понравившуюся книгу. Передавайте вещи лично и заранее договаривайтесь в комментариях, если хотите встретиться с конкретным участником."),
        (4, "news", "Собираем команду на студенческий хакатон", "science", "coding", None, None, None, None, "Ищем разработчика интерфейса, дизайнера и человека, которому интересно работать с данными. Хотим сделать небольшой, но законченный продукт и проверить его на реальных пользователях.\n\nЗнание конкретного стека не обязательно. Важнее готовность договариваться, показывать промежуточный результат и доводить задачи до конца. Напишите в комментариях, что вам интересно и какие проекты уже пробовали делать."),
        (6, "event", "Лёгкая пробежка перед занятиями", "sport", "sport", 4, 8, "Набережная · встреча у пешеходного входа", "Бесплатно", "Бежим в разговорном темпе около трёх километров. Сначала короткая разминка, в конце — спокойная заминка. Никто не останется один: начнём и закончим вместе.\n\nМаршрут подходит для первой групповой пробежки. Оденьтесь по погоде и возьмите воду. При сильном дожде перенесём встречу и обновим эту публикацию после проверки модератором."),
        (8, "news", "Что помогает освоиться на первом курсе", "campus", "campus", None, None, None, None, "За первые недели собрал несколько привычек, которые действительно экономят время. Сохраняю расписание на неделю, записываю дедлайны в одно место и заранее проверяю аудиторию перед парой.\n\nЕщё помогает задавать вопросы старшекурсникам и не пытаться сразу вступить во все сообщества. Выберите одно занятие, которое интересно именно вам, и сходите на встречу. В комментариях можно дополнить список своими советами."),
        (7, "event", "Разбор резюме: первая стажировка", "career", "coding", 5, 16, "Коворкинг · переговорная", "Бесплатно", "Практическая встреча: посмотрим, как описывать учебные проекты, какой объём резюме удобен для чтения и почему конкретные примеры сильнее общих формулировок.\n\nМожно принести собственный черновик или работать с учебным примером. Персональные данные показывать не обязательно. После встречи останется шаблон структуры, который можно заполнить самостоятельно."),
        (3, "event", "Фотопрогулка по осенней Уфе", "culture", "culture", 6, 14, "Встреча у главного входа в кампус", "Бесплатно", "Пройдём короткий маршрут по центру города и попробуем снять знакомые места с нового ракурса. Подойдёт любой телефон или фотоаппарат.\n\nПо дороге поговорим о свете и композиции, а в конце выберем по одному кадру для общей подборки. Возьмите удобную обувь. Если будет холодно, зайдём погреться и посмотрим фотографии вместе."),
        (5, "news", "Мини-исследование: сколько одноразовых стаканов мы используем", "science", "science", None, None, None, None, "Начинаем небольшой студенческий проект о повседневных привычках. Хотим за неделю собрать анонимные наблюдения и понять, в каких ситуациях многоразовая кружка оказывается удобнее одноразового стакана.\n\nСейчас выбираем простой способ учёта и вопросы для короткой анкеты. Если у вас есть опыт опросов или визуализации данных, будем рады советам. Итоги и ограничения исследования опубликуем отдельным материалом."),
        (7, "event", "Настольные игры после пар", "community", "community", 0, 17, "Студенческое пространство · большой стол", "Бесплатно", "Встречаемся после занятий: принесём несколько быстрых настольных игр, объясним правила и соберём небольшие компании. Можно присоединиться одному — организаторы помогут выбрать стол.\n\nЕсли хотите принести свою игру, напишите её название в комментариях. Запланировали два часа, но можно прийти позже или уйти раньше."),
        (6, "news", "Ищем напарников для регулярных тренировок", "sport", "sport", None, None, None, None, "Когда заранее договорился с кем-то о тренировке, пропустить её сложнее. Собираем небольшую группу для занятий два раза в неделю: общая разминка, упражнения с собственным весом и растяжка.\n\nПока выбираем время и удобную площадку. Напишите в комментариях, в какие дни вы свободны и какой формат вам подходит. Участники сами определяют комфортную нагрузку."),
        (8, "news", "Свободный стол для совместной учёбы", "community", "community", None, None, None, None, "Ищем компанию для спокойной совместной подготовки: каждый работает над своим предметом, а в перерывах можно обсудить сложные вопросы. Попробуем формат 45 минут работы и 10 минут отдыха.\n\nДля первой встречи достаточно трёх-четырёх человек. Укажите в комментариях предмет и удобное время. Если идея приживётся, будем собираться раз в неделю."),
    ]
    post_ids = []
    for index, (author, kind, title, category, cover, offset, hour, location, price, body) in enumerate(samples):
        published = stamp(local - timedelta(hours=index * 3 + 1))
        event_start = day + timedelta(days=offset, hours=hour) if offset is not None else None
        event_end = event_start + timedelta(hours=2) if event_start else None
        cursor = connection.execute("INSERT INTO posts(author_id,type,title,body,category,cover_url,status,created_at,updated_at,published_at,event_start,event_end,location,price,is_demo) VALUES(?,?,?,?,?,?,'published',?,?,?,?,?,?,?,1)", (author, kind, title, body, category, f"/media/covers/{cover}.jpg", published, published, published, stamp(event_start) if event_start else None, stamp(event_end) if event_end else None, location, price))
        post_ids.append(cursor.lastrowid)
        connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,created_at) VALUES(?,2,'publish',?)", (cursor.lastrowid, published))
        for demo_user in range(3, 9):
            if (index + demo_user) % 3 != 0:
                reaction = ["like", "fire", "heart", "clap"][(index + demo_user) % 4]
                connection.execute("INSERT INTO reactions(user_id,post_id,reaction) VALUES(?,?,?)", (demo_user, cursor.lastrowid, reaction))
            if kind == "event" and (index + demo_user) % 2 == 0:
                connection.execute("INSERT INTO attendance(user_id,post_id) VALUES(?,?)", (demo_user, cursor.lastrowid))

    discussions = [
        (post_ids[0], 8, "Если с Flutter ещё не работал, можно присоединиться?", None),
        (post_ids[0], 4, "Конечно. Начнём с основ, а дальше разделимся по уровню. Ноутбук захвати.", 1),
        (post_ids[0], 1, "Я приду. Могу помочь с Python и подключением API.", None),
        (post_ids[0], 7, "Есть ли место, где можно будет зарядить ноутбук?", None),
        (post_ids[0], 4, "Да, розетки рядом со столами есть. На всякий случай возьму удлинитель.", 4),
        (post_ids[2], 1, "Давно хотел вернуться к баскетболу. Уровень любительский, записался.", None),
        (post_ids[2], 6, "Отлично, будем рады. Начнём с простых упражнений.", 6),
        (post_ids[4], 8, "Предлагаю «Невероятную жизнь Уолтера Митти».", None),
        (post_ids[4], 3, "Хороший вариант, добавила в список. Ещё предложения?", 8),
        (post_ids[13], 3, "Принесу Dixit, если найдётся ещё четыре человека.", None),
        (post_ids[13], 5, "Я за! Как раз хотела попробовать.", 10),
        (post_ids[7], 1, "Могу заняться серверной частью. Как лучше обсудить идею?", None),
        (post_ids[7], 4, "Давай встретимся на вечере кода, заодно посмотрим, кто ещё хочет присоединиться.", 12),
        (post_ids[1], 5, "Первый кадр очень тёплый. Осенью кампус особенно красивый.", None),
        (post_ids[9], 1, "Ещё советую заранее находить аудитории, если занятия в незнакомом корпусе.", None),
    ]
    for index, (post_id, author, body, parent) in enumerate(discussions):
        connection.execute("INSERT INTO comments(post_id,author_id,body,created_at,parent_id) VALUES(?,?,?,?,?)", (post_id, author, body, stamp(local - timedelta(minutes=90 - index * 3)), parent))
    for following in (3, 4, 6):
        connection.execute("INSERT INTO follows(follower_id,following_id) VALUES(1,?)", (following,))
    for follower, following in ((3, 4), (4, 3), (5, 1), (6, 1), (7, 3), (8, 4), (4, 1), (3, 1), (6, 4)):
        connection.execute("INSERT INTO follows(follower_id,following_id) VALUES(?,?)", (follower, following))
    for friend in (4, 6):
        connection.execute("INSERT INTO friendships(user_low,user_high,requester_id,created_at,accepted_at) VALUES(1,?,1,?,?)", (friend, created, stamp(local - timedelta(days=7))))
    connection.execute("INSERT INTO friendships(user_low,user_high,requester_id,created_at) VALUES(1,5,5,?)", (stamp(local - timedelta(hours=1)),))
    connection.execute("INSERT INTO bookmarks(user_id,post_id) VALUES(1,?)", (post_ids[0],))
    connection.execute("INSERT INTO bookmarks(user_id,post_id) VALUES(1,?)", (post_ids[3],))

    draft_at = stamp(local - timedelta(minutes=35))
    connection.execute("INSERT INTO posts(author_id,type,title,body,category,status,created_at,updated_at,is_demo) VALUES(1,'news',?,?,?,'draft',?,?,1)", ("Собираю команду для учебного приложения", "Хочу сделать небольшое приложение для студентов и ищу тех, кому интересно попробовать дизайн, мобильную разработку или работу с сервером. Сначала обсудим одну понятную задачу и сделаем работающий прототип.", "science", draft_at, draft_at))
    pending_cursor = connection.execute("INSERT INTO posts(author_id,type,title,body,category,status,created_at,updated_at,is_demo) VALUES(1,'news',?,?,?,'pending',?,?,1)", ("Обмен учебниками по программированию", "Есть несколько учебников по основам Python и алгоритмам. Готов обменять на книги по мобильной разработке или передать первокурсникам. В комментариях можно написать, какие темы вам интересны.", "community", draft_at, draft_at))
    connection.execute("INSERT INTO moderation_history(post_id,actor_id,decision,created_at) VALUES(?,1,'submitted',?)", (pending_cursor.lastrowid, draft_at))
    connection.execute("INSERT INTO notifications(user_id,title,body,post_id,created_at) VALUES(1,?,?,?,?)", ("Публикация на проверке", "«Обмен учебниками по программированию» отправлена модератору. Результат появится здесь.", pending_cursor.lastrowid, draft_at))
