"""Two authorized real OpenRouter checks; prints only decisions and usage."""
from pathlib import Path
import json
import secrets
import sys
from contextlib import closing
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from backend.main import create_app
from backend.database import connect
from backend.ai_moderation import AiModerator, queue_review

runtime = ROOT / 'runtime' / 'server'
database = runtime / 'tmp' / ('ai-live-' + secrets.token_hex(4) + '.sqlite3')
app = create_app(database, seed_demo=False, upload_dir=runtime / 'tmp' / 'ai-check-uploads')
results = []
with TestClient(app) as client:
    session = client.post('/api/auth/register', json={'email': 'ai-check@example.com', 'password': secrets.token_urlsafe(20), 'name': 'Проверка ИИ'}).json()
    headers = {'Authorization': 'Bearer ' + session['token']}
    cases = [
        ('ordinary_with_photo', 'Открытая встреча студенческой лаборатории', 'Приглашаем студентов на открытую встречу лаборатории. Обсудим учебные проекты, покажем оборудование и ответим на вопросы. Вход свободный.', ['/media/covers/science.jpg']),
        ('phishing', 'Срочное сообщение для всех студентов', 'От имени деканата просим срочно передать нам пароль от банковского приложения и одноразовый код из SMS. Иначе вашу стипендию заблокируют. Отправляйте коды в личные сообщения организатору.', []),
    ]
    worker = AiModerator(database, runtime / 'openrouter.key', runtime / 'tmp' / 'ai-check-uploads', ROOT / 'backend' / 'media', budget=1.6)
    for name, title, body, images in cases:
        response = client.post('/api/posts', headers=headers, json={'title': title, 'body': body, 'category': 'science', 'image_urls': images, 'submit': True})
        response.raise_for_status()
        post_id = response.json()['id']
        with closing(connect(database)) as connection, connection:
            queue_review(connection, post_id, True)
        worker.run_one()
        with closing(connect(database)) as connection:
            row = dict(connection.execute('SELECT status,reason,provider,cost_usd,images_checked FROM ai_reviews WHERE post_id=?', (post_id,)).fetchone())
        results.append({'case': name, **row})
        if row['status'] == 'unavailable':
            break
report = {'model': 'deepseek/deepseek-v4.1-flash-1017', 'checks': results, 'cost_usd': sum(row['cost_usd'] for row in results)}
(runtime / 'ai-live-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
if [row['status'] for row in results] != ['approved', 'changes_requested']:
    raise SystemExit('Real AI check needs attention; see the sanitized report')
