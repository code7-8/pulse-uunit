import json
from contextlib import closing
from pathlib import Path
import httpx
import pytest
from fastapi.testclient import TestClient
from backend.main import create_app, ROOT
from backend.database import connect
from backend.ai_moderation import AiModerator, queue_review, MODEL, RESERVATION


@pytest.fixture
def setup(tmp_path, monkeypatch):
    monkeypatch.setenv('PULSE_AI_ENABLED', 'true')
    monkeypatch.setattr(AiModerator, 'start', lambda self: None)
    app = create_app(tmp_path / 'db.sqlite3', seed_demo=False, upload_dir=tmp_path / 'uploads')
    key = tmp_path / 'test.key'
    key.write_text('test-only-key')
    with TestClient(app) as client:
        auth = client.post('/api/auth/register', json={'name':'Автор теста','email':'author@example.com','password':'Password123!'}).json()
        yield client, app, {'Authorization':'Bearer '+auth['token']}, key


def post(client, headers, **extra):
    response = client.post('/api/posts', headers=headers, json={'title':'Открытая встреча студентов','body':'Приглашаем студентов обсудить учебные проекты и найти команду.', 'category':'science', **extra})
    assert response.status_code == 201, response.text
    return response.json()


def worker(app, key, handler, budget=1.6):
    client = httpx.Client(transport=httpx.MockTransport(handler))
    return AiModerator(app.state.db_path, key, app.state.image_storage.roots[0] if hasattr(app.state.image_storage, 'roots') else key.parent/'uploads', ROOT/'media', budget=budget, client=client)


def result(decision='approve'):
    return httpx.Response(200,json={'provider':'TestProvider','usage':{'cost':0.0002},'choices':[{'message':{'content':json.dumps({'decision':decision,'reason':'Уберите запрос чужих банковских паролей' if decision=='changes_requested' else 'Явных нарушений не обнаружено'})}}]})


def test_gallery_order_limit_and_clearing(setup):
    client, app, headers, key = setup
    images = ['/media/covers/science.jpg','/media/covers/coding.jpg','/media/covers/campus.jpg']
    created = post(client, headers, image_urls=images, submit=False)
    assert created['image_urls'] == images and created['cover_url'] == images[0]
    changed=client.patch(f"/api/posts/{created['id']}",headers=headers,json={'image_urls':images[::-1]}).json()
    assert changed['image_urls']==images[::-1] and changed['cover_url']==images[-1]
    assert client.patch(f"/api/posts/{created['id']}",headers=headers,json={'image_urls':images*3}).status_code==422
    cleared=client.patch(f"/api/posts/{created['id']}",headers=headers,json={'image_urls':[]}).json()
    assert cleared['cover_url'] is None and cleared['image_urls']==[]


def test_topic_subscriptions_include_unfollowed_authors_and_persist(setup):
    client, app, headers, key = setup
    science=post(client, headers, submit=False)
    career=post(client, headers, category='career', submit=False)
    with closing(connect(app.state.db_path)) as db, db:
        db.execute("UPDATE posts SET status='published'")
    assert client.get('/api/posts?feed=following',headers=headers).json()['total']==0
    assert client.put('/api/categories/science/follow',headers=headers).json()['interests']==['science']
    assert [p['id'] for p in client.get('/api/posts?feed=following',headers=headers).json()['items']]==[science['id']]
    assert next(c for c in client.get('/api/categories',headers=headers).json() if c['id']=='science')['is_following']
    assert client.put('/api/categories/science/follow',headers=headers).json()['interests']==['science']
    assert client.get('/api/me',headers=headers).json()['interests']==['science']
    client.delete('/api/categories/science/follow',headers=headers)
    assert client.get('/api/posts?feed=following',headers=headers).json()['total']==0
    assert client.put('/api/categories/science/follow').status_code==401


def test_ai_reviews_text_and_local_photos_but_only_humans_can_publish(setup):
    client, app, headers, key=setup
    created=post(client,headers,image_urls=['/media/covers/science.jpg','/media/covers/campus.jpg'])
    assert created['ai_review']['status']=='queued'
    def respond(request):
        payload=json.loads(request.content)
        assert payload['model']==MODEL and payload['provider']['sort']=='price'
        assert payload['max_tokens']<=350 and payload['reasoning']['effort']=='none'
        assert 'test-only-key' not in request.content.decode()
        assert len(payload['messages'][1]['content'])==3
        assert all(image['image_url']['url'].startswith('data:image/jpeg;base64,') for image in payload['messages'][1]['content'][1:])
        return result()
    assert worker(app,key,respond).run_one()
    updated=client.get(f"/api/posts/{created['id']}",headers=headers).json()
    assert updated['status']=='pending' and updated['ai_review']['status']=='approved'
    assert updated['ai_review']['images_checked']==2
    assert client.get(f"/api/posts/{created['id']}").status_code==404


def test_ai_rejection_can_be_appealed_to_a_human_without_new_charge(setup):
    client, app, headers, key=setup
    created=post(client,headers)
    worker(app,key,lambda r:result('changes_requested')).run_one()
    returned=client.get(f"/api/posts/{created['id']}",headers=headers).json()
    assert returned['status']=='changes_requested' and returned['moderation_reason']
    appeal=client.post(f"/api/posts/{created['id']}/appeal",headers=headers)
    assert appeal.status_code==200 and appeal.json()['status']=='pending'
    assert appeal.json()['ai_review']['status']=='appealed'
    with closing(connect(app.state.db_path)) as db:
        assert db.execute('SELECT COUNT(*) FROM ai_reviews WHERE post_id=?',(created['id'],)).fetchone()[0]==1


def test_stale_ai_cannot_reverse_a_human_decision(setup):
    client, app, headers, key=setup
    created=post(client,headers)
    def respond(request):
        with closing(connect(app.state.db_path)) as db, db:
            db.execute("UPDATE posts SET status='published',updated_at='2026-10-24T15:00:00Z' WHERE id=?",(created['id'],))
        return result('changes_requested')
    worker(app,key,respond).run_one()
    assert client.get(f"/api/posts/{created['id']}").json()['status']=='published'
    with closing(connect(app.state.db_path)) as db:
        assert db.execute('SELECT status FROM ai_reviews WHERE post_id=?',(created['id'],)).fetchone()[0]=='obsolete'


def test_budget_exhaustion_falls_back_to_human_without_request(setup):
    client, app, headers, key=setup
    created=post(client,headers)
    def forbidden(request):
        pytest.fail('Budget exhaustion must not call OpenRouter')
    worker(app,key,forbidden,budget=0).run_one()
    current=client.get(f"/api/posts/{created['id']}",headers=headers).json()
    assert current['status']=='pending' and current['ai_review']['status']=='manual'


def test_external_image_urls_are_not_fetched_by_the_server(setup):
    client, app, headers, key=setup
    created=post(client,headers,image_urls=['https://example.com/photo.jpg'])
    def respond(request):
        assert request.url.host=='openrouter.ai'
        payload=json.loads(request.content)
        assert len(payload['messages'][1]['content'])==1
        return result()
    worker(app,key,respond).run_one()
    current=client.get(f"/api/posts/{created['id']}",headers=headers).json()
    assert current['ai_review']['status']=='manual' and current['ai_review']['images_checked']==0


def test_provider_html_error_falls_back_to_human_and_keeps_budget_reservation(setup):
    client, app, headers, key=setup
    created=post(client,headers)
    worker(app,key,lambda request:httpx.Response(502,text='<html>Gateway unavailable</html>')).run_one()
    current=client.get(f"/api/posts/{created['id']}",headers=headers).json()
    assert current['status']=='pending' and current['ai_review']['status']=='unavailable'
    with closing(connect(app.state.db_path)) as db:
        assert db.execute('SELECT cost_usd FROM ai_reviews WHERE post_id=?',(created['id'],)).fetchone()[0]==RESERVATION
