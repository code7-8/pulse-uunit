import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse/services/demo_api_client.dart';
import 'package:pulse/state/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'A newly registered demo profile gets contacts and photo chats once, retaining its choices after reopening',
    () async {
      final api = DemoApiClient();
      final session = await api.request(
        'POST',
        '/auth/register',
        body: {
          'email': 'reviewer@example.com',
          'password': 'TestPassword123!',
          'name': 'Проверяющий',
        },
      );
      expect(session['user']['friends_count'], 2);
      final friends = (await api.request('GET', '/friends'))['items'] as List;
      expect(friends.length, 2);
      expect(
        friends.every(
          (friend) =>
              friend['bio'].toString().contains('Демонстрационный профиль'),
        ),
        true,
      );
      final requests =
          (await api.request('GET', '/friends/requests'))['incoming'] as List;
      expect(requests.length, 1);
      final chats = (await api.request('GET', '/chats'))['items'] as List;
      expect(chats.length, 2);
      expect(chats.every((chat) => chat['can_send'] == true), true);
      final messages = <dynamic>[];
      for (final chat in chats) {
        messages.addAll(
          (await api.request('GET', '/chats/${chat['id']}/messages'))['items']
              as List,
        );
      }
      final photo = messages.singleWhere(
        (message) => message['image_url'] != null,
      );
      expect(
        (await api.downloadPrivateImage(photo['image_url'] as String)).length,
        greaterThan(1000),
      );
      await api.request('DELETE', '/users/${friends.first['id']}/friendship');
      final token = api.token;
      api.close();
      final reopened = DemoApiClient()..token = token;
      expect(
        ((await reopened.request('GET', '/friends'))['items'] as List).length,
        1,
      );
      expect(
        ((await reopened.request('GET', '/chats'))['items'] as List).length,
        2,
      );
      reopened.close();
    },
  );

  test(
    'Offline startup opens a student profile and loads bundled news and categories',
    () async {
      final api = DemoApiClient();
      final controller = AppController(api: api);
      await controller.initialize();
      expect(controller.error, isNull);
      expect(controller.user?.id, '1');
      expect(controller.categories.length, 6);
      expect(controller.posts.length, 16);
      expect(
        controller.posts.every((p) => p.coverUrl.startsWith('assets/demo/')),
        true,
      );
      expect(api.isOffline, true);
      expect(controller.baseUrl, 'demo://local');
      expect(controller.accent, const Color(0xFF4D19CC));
      expect(controller.themeMode, ThemeMode.light);
      controller.dispose();
    },
  );

  test(
    'An existing appearance choice survives the university default and reopening',
    () async {
      SharedPreferences.setMockInitialValues({
        'accent': 0xFF278363,
        'theme': 'dark',
      });
      final first = AppController(api: DemoApiClient());
      await first.initialize();
      expect(first.accent, const Color(0xFF278363));
      expect(first.themeMode, ThemeMode.dark);
      first.setAppearance(
        accent: const Color(0xFF4D19CC),
        mode: ThemeMode.light,
      );
      first.dispose();
      final reopened = AppController(api: DemoApiClient());
      await reopened.initialize();
      expect(reopened.accent, const Color(0xFF4D19CC));
      expect(reopened.themeMode, ThemeMode.light);
      reopened.dispose();
    },
  );

  test(
    'Local likes, bookmarks and comments survive reopening the demo',
    () async {
      final api = DemoApiClient()..token = 'demo-1';
      final feed = await api.request('GET', '/posts');
      final id = (feed['items'] as List).first['id'];
      await api.request(
        'PUT',
        '/posts/$id/reaction',
        body: {'reaction': 'fire'},
      );
      await api.request('PUT', '/posts/$id/bookmark');
      await api.request(
        'POST',
        '/posts/$id/comments',
        body: {'body': 'Проверяем обсуждение без подключения к сети.'},
      );
      api.close();
      final reopened = DemoApiClient()..token = 'demo-1';
      final post = await reopened.request('GET', '/posts/$id');
      expect(post['my_reaction'], 'fire');
      expect(post['is_bookmarked'], true);
      final comments = await reopened.request('GET', '/posts/$id/comments');
      expect(
        (comments['items'] as List).last['body'],
        'Проверяем обсуждение без подключения к сети.',
      );
      reopened.close();
    },
  );

  test('The full author and moderator workflow works locally', () async {
    final api = DemoApiClient();
    final controller = AppController(api: api);
    await controller.initialize();
    final draft = await controller.createPost({
      'type': 'news',
      'category': 'campus',
      'title': 'Проверка автономной публикации',
      'body': 'Публикация проходит проверку полностью на этом телефоне.',
      'submit': false,
    });
    await controller.submitPost(draft.id);
    await controller.loadFeed(mode: 'all', query: 'Проверка автономной');
    expect(controller.posts, isEmpty);
    await controller.login('moderator@pulse.local', 'Moderator123!');
    await controller.loadModeration();
    expect(controller.moderationPosts.any((p) => p.id == draft.id), true);
    await controller.moderate(
      draft.id,
      'return',
      reason: 'Добавьте место встречи.',
    );
    await controller.login('student@pulse.local', 'Student123!');
    await controller.loadMyPosts();
    expect(
      controller.myPosts.firstWhere((p) => p.id == draft.id).moderationReason,
      'Добавьте место встречи.',
    );
    await controller.updatePost(draft.id, {
      'body': 'Проверка на телефоне. Встречаемся в университетском коворкинге.',
      'submit': false,
    });
    await controller.submitPost(draft.id);
    await controller.login('moderator@pulse.local', 'Moderator123!');
    await controller.loadModeration();
    await controller.moderate(draft.id, 'approve');
    await controller.loadFeed(mode: 'all', query: 'Проверка автономной');
    expect(controller.posts.single.id, draft.id);
    expect(
      (await controller.loadModerationHistory(draft.id)).length,
      greaterThanOrEqualTo(4),
    );
    controller.dispose();
  });

  test(
    'Photo messages and their contents are available after reopening without a server',
    () async {
      final api = DemoApiClient()..token = 'demo-1';
      final bytes = (await rootBundle.load(
        'assets/demo/coding.jpg',
      )).buffer.asUint8List();
      final photo = await api.upload(
        bytes,
        'photo.jpg',
        path: '/chats/1/images',
      );
      expect(photo.startsWith('data:image/'), true);
      final sent = await api.request(
        'POST',
        '/chats/1/messages',
        body: {'body': 'Фото для теста', 'image_url': photo},
      );
      api.close();
      final reopened = DemoApiClient()..token = 'demo-1';
      final messages = await reopened.request('GET', '/chats/1/messages');
      expect((messages['items'] as List).last['id'], sent['id']);
      expect(await reopened.downloadPrivateImage(photo), bytes);
      expect(
        (await reopened.downloadPrivateImage('assets/demo/coding.jpg')).length,
        bytes.length,
      );
      reopened.close();
    },
  );

  test('Accepting a demo friend updates local event recommendations', () async {
    final api = DemoApiClient()..token = 'demo-1';
    final requests = await api.request('GET', '/friends/requests');
    expect((requests['incoming'] as List), isNotEmpty);
    final person = requests['incoming'].first['id'];
    await api.request('POST', '/users/$person/friend-request/accept');
    final profile = await api.request('GET', '/users/$person');
    expect(profile['friendship_status'], 'friends');
    final friends = await api.request('GET', '/friends');
    expect((friends['items'] as List).length, 3);
    final recommended = await api.request(
      'GET',
      '/posts',
      query: {'feed': 'friends'},
    );
    expect((recommended['items'] as List), isNotEmpty);
    expect(
      (recommended['items'] as List).every(
        (p) => p['friends_attending_count'] > 0,
      ),
      true,
    );
    api.close();
  });

  test(
    'Seed data contains no server sessions or real account password hashes',
    () async {
      final seed =
          jsonDecode(await rootBundle.loadString('assets/demo/seed.json'))
              as Map;
      expect(seed.containsKey('sessions'), false);
      expect(
        (seed['users'] as List).every((u) => !u.containsKey('password_hash')),
        true,
      );
    },
  );
}
