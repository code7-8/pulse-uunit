# Материалы и зависимости

## Контекст

Кейс «Умное решение для ленты новостей» из предоставленной презентации хакатона. Название университета уточнено пользователем. Справочная проверка структуры студенческой жизни: https://uust.ru/for-students/ . Прототип не использует университетскую авторизацию и не представляет официальный сервис.

## Фотографии демо-ленты

Иллюстрации Unsplash показывают общие сюжеты. Они не являются фотографиями анонсируемых событий или конкретных корпусов УУНиТ. Условия: https://unsplash.com/license . В проекте используются локальные копии для устойчивого показа без внешнего CDN.

| Файл | Источник |
| --- | --- |
| campus.jpg | https://images.unsplash.com/photo-1523580494863-6f3031224c94 |
| coding.jpg | https://images.unsplash.com/photo-1516321318423-f06f85e504b3 |
| science.jpg | https://images.unsplash.com/photo-1532094349884-543bc11b234d |
| sport.jpg | https://images.unsplash.com/photo-1546519638-68e109498ffc |
| culture.jpg | https://images.unsplash.com/photo-1506157786151-b8491531f063 |
| community.jpg | https://images.unsplash.com/photo-1529156069898-49953e39b3ac |

## Шрифт

Manrope, SIL Open Font License 1.1. Файл лицензии: `mobile/assets/fonts/OFL.txt`. Исходник: https://github.com/google/fonts/tree/main/ofl/manrope .

## Документация

- Flutter: https://docs.flutter.dev/
- FastAPI и SQLite: https://fastapi.tiangolo.com/tutorial/sql-databases/
- Flutter HTTP: https://pub.dev/packages/http
- Защищённое хранение сессии: https://pub.dev/packages/flutter_secure_storage
- Выбор фотографии: https://pub.dev/packages/image_picker
- Открытие ссылки: https://pub.dev/packages/url_launcher

# Оформление УУНИТ

Официальный брендбук: https://uust.ru/brandbook/ . Фиолетовый `#4D19CC`, сиреневый `#CBB8FF`, тёмно-фиолетовый `#2A1468`. В приложении эта палитра начальная при отсутствии сохранённых настроек. Приложение остаётся самостоятельным прототипом хакатона.

Golos Text: https://github.com/google/fonts/tree/main/ofl/golostext . SIL Open Font License 1.1, копия: `mobile/assets/fonts/GolosText-OFL.txt`.

## Обнаружение сервера

- API бесплатного публичного каталога: https://superjsonblob.com/api-docs . Запись содержит только подписанный адрес; это не хранилище данных пользователей.
- Ed25519 в Dart: https://pub.dev/documentation/cryptography/latest/cryptography/Ed25519-class.html .
- Ed25519 в Python: https://cryptography.io/en/latest/hazmat/primitives/asymmetric/ed25519/ .


## Модерация

- DeepSeek 1017: https://openrouter.ai/deepseek/deepseek-v4.1-flash-1017 .
- Выбор провайдера по цене: https://openrouter.ai/docs/guides/routing/provider-selection .
