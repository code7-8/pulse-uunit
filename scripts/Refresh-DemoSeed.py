"""Build bundled fiction from a fresh temporary database, never from real users."""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
from contextlib import closing

WORKSPACE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKSPACE))
from backend.database import connect, SCHEMA
from backend.seed import seed, stamp
from backend.review_demo import prepare_review_users

temporary_root = WORKSPACE / 'runtime' / 'server' / 'tmp'
temporary_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='fictional-seed-', dir=temporary_root) as directory:
    if not Path(directory).resolve().is_relative_to(temporary_root.resolve()):
        raise ValueError('Temporary seed directory escaped the project')
    path = Path(directory) / 'seed.sqlite3'
    with closing(connect(path)) as connection, connection:
        connection.executescript(SCHEMA)
        seed(connection, include_demo=True)
        prepare_review_users(connection)
        tables = ('users', 'categories', 'posts', 'follows', 'friendships', 'bookmarks', 'reactions',
            'attendance', 'comments', 'moderation_history', 'comment_reports', 'notifications', 'conversations', 'messages')
        data = {table: [dict(row) for row in connection.execute('SELECT * FROM ' + table)] for table in tables}
    for user in data['users']:
        user.pop('password_hash')
        user['interests'] = json.loads(user['interests'])
    for post in data['posts']:
        post['image_urls'] = [url.replace('/media/covers/', 'assets/demo/') for url in json.loads(post['image_urls'])]
        if post['cover_url']:
            post['cover_url'] = post['cover_url'].replace('/media/covers/', 'assets/demo/')
    # A bundled photo is available immediately; online images use private routes.
    peer_id = next(user['id'] for user in data['users'] if user['email'] == 'timur@pulse.local')
    chat = next(chat for chat in data['conversations'] if {chat['user_low'], chat['user_high']} == {1, peer_id})
    now = datetime.now(timezone.utc)
    data['messages'].append({'id': max((message['id'] for message in data['messages']), default=0) + 1,
        'conversation_id': chat['id'], 'sender_id': peer_id, 'body': 'Фотография с прошлой встречи.',
        'image_url': 'assets/demo/coding.jpg', 'created_at': stamp(now - timedelta(minutes=5)), 'read_at': None})
    data['generated_at'] = stamp(now)
    destination = WORKSPACE / 'mobile' / 'assets' / 'demo' / 'seed.json'
    destination.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"Bundled fiction: {len(data['users'])} profiles, {len(data['posts'])} publications, {len(data['comments'])} comments")
