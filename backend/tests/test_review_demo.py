from fastapi.testclient import TestClient
from backend.database import connect
from backend.main import create_app


def signup(client, email):
    response = client.post('/api/auth/register', json={'email': email, 'password': 'ReviewPassword123!', 'name': 'Участник проверки'})
    assert response.status_code == 201, response.text
    session = response.json()
    return session['user'], {'Authorization': 'Bearer ' + session['token']}


def test_new_review_accounts_have_feed_discussions_friends_requests_and_private_chats(tmp_path):
    app = create_app(tmp_path / 'db.sqlite3', seed_demo=True, review_demo=True, upload_dir=tmp_path / 'uploads')
    with TestClient(app) as client:
        user, headers = signup(client, 'first@example.com')
        outsider, other_headers = signup(client, 'second@example.com')
        posts = client.get('/api/posts?page_size=100', headers=headers).json()['items']
        assert len(posts) == 16 and all(post['comments_count'] >= 2 for post in posts)
        friends = client.get('/api/friends', headers=headers).json()['items']
        assert len(friends) == 2
        assert all('Демонстрационный профиль' in friend['bio'] for friend in friends)
        assert outsider['id'] not in [friend['id'] for friend in friends]
        requests = client.get('/api/friends/requests', headers=headers).json()
        assert len(requests['incoming']) == 1 and requests['outgoing'] == []
        chats = client.get('/api/chats', headers=headers).json()['items']
        assert len(chats) == 2 and all(chat['can_send'] and chat['unread_count'] > 0 for chat in chats)
        photo_messages = []
        for chat in chats:
            response = client.get(f"/api/chats/{chat['id']}/messages", headers=headers)
            assert response.status_code == 200
            photo_messages += [item for item in response.json()['items'] if item['image_url']]
            assert client.get(f"/api/chats/{chat['id']}/messages", headers=other_headers).status_code == 404
        assert len(photo_messages) == 1
        photo = photo_messages[0]['image_url']
        assert client.get(photo, headers=headers).status_code == 200
        assert client.get(photo, headers=other_headers).status_code == 404
        assert client.get('/api/posts?feed=friends', headers=headers).json()['total'] > 0
        applicant = requests['incoming'][0]['id']
        assert client.post(f'/api/users/{applicant}/friend-request/accept', headers=headers).status_code == 200
        assert client.get('/api/friends', headers=headers).json()['total'] == 3


def test_review_restart_keeps_user_choices_and_does_not_duplicate_chats_or_messages(tmp_path):
    app = create_app(tmp_path / 'db.sqlite3', seed_demo=True, review_demo=True, upload_dir=tmp_path / 'uploads')
    with TestClient(app) as client:
        user, headers = signup(client, 'persistent@example.com')
        with connect(app.state.db_path) as db:
            counts = tuple(db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0] for table in ('messages', 'conversations', 'comments'))
            db.execute('DELETE FROM friendships WHERE user_low=? OR user_high=?', (user['id'], user['id']))
    with TestClient(app) as client:
        assert client.get('/api/friends', headers=headers).json()['total'] == 0
        assert client.get('/api/friends/requests', headers=headers).json()['incoming'] == []
        with connect(app.state.db_path) as db:
            assert tuple(db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0] for table in ('messages', 'conversations', 'comments')) == counts


def test_normal_registration_does_not_add_demo_relationships(tmp_path):
    with TestClient(create_app(tmp_path / 'db.sqlite3', seed_demo=True, review_demo=False, upload_dir=tmp_path / 'uploads')) as client:
        user, headers = signup(client, 'normal@example.com')
        assert client.get('/api/friends', headers=headers).json()['total'] == 0
        assert client.get('/api/chats', headers=headers).json()['total'] == 0
        assert client.get('/api/friends/requests', headers=headers).json()['incoming'] == []
