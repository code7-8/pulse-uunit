import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/domain/models.dart';
import 'package:pulse/services/demo_api_client.dart';
import 'package:pulse/state/app_controller.dart';
import 'package:pulse/ui/publication_extras.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/fake_pulse_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Offline galleries preserve order and topic following includes authors who were not followed',
    () async {
      final api = DemoApiClient();
      await api.request(
        'POST',
        '/auth/register',
        body: {
          'name': 'Проверяющий',
          'email': 'gallery@example.com',
          'password': 'Password123!',
        },
      );
      final images = [
        'assets/demo/science.jpg',
        'assets/demo/campus.jpg',
        'assets/demo/coding.jpg',
      ];
      final post = await api.request(
        'POST',
        '/posts',
        body: {
          'title': 'Открытая встреча лаборатории',
          'body': 'Студенты представят свои проекты и ответят на вопросы.',
          'category': 'science',
          'image_urls': images,
          'submit': false,
        },
      );
      expect(post['image_urls'], images);
      expect(post['cover_url'], images.first);
      final changed = await api.request(
        'PATCH',
        '/posts/${post['id']}',
        body: {'image_urls': images.reversed.toList()},
      );
      expect(changed['image_urls'], images.reversed.toList());
      final before =
          (await api.request(
                'GET',
                '/posts',
                query: {'feed': 'following'},
              ))['items']
              as List;
      expect(before.any((post) => post['author']['id'] == 5), false);
      await api.request('PUT', '/categories/science/follow');
      final after =
          (await api.request(
                'GET',
                '/posts',
                query: {'feed': 'following'},
              ))['items']
              as List;
      expect(after.any((post) => post['author']['id'] == 5), true);
      final reopened = DemoApiClient()..token = api.token;
      expect(
        (await reopened.request('GET', '/me'))['interests'],
        contains('science'),
      );
      expect(
        (await reopened.request('GET', '/posts/${post['id']}'))['image_urls'],
        images.reversed.toList(),
      );
      api.close();
      reopened.close();
    },
  );

  testWidgets('Gallery swipes and opens the selected image full screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FakePulseController()..baseUrl = 'demo://local';
    final post = CampusPost(
      id: 'gallery',
      title: 'Галерея',
      body: 'Пример публикации',
      author: c.user!,
      imageUrls: const [
        'assets/demo/science.jpg',
        'assets/demo/campus.jpg',
        'assets/demo/coding.jpg',
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostGallery(controller: c, post: post),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsWidgets);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('Topic subscriptions can be changed from a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = AppController(api: DemoApiClient());
    await tester.runAsync(c.initialize);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTopics(context, c),
              child: const Text('Темы'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Темы'));
    await tester.pumpAndSettle();
    expect(find.text('Мои темы'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(c.user!.interests, contains('campus'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('AI status and human appeal are visible without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FakePulseController();
    final post = CampusPost(
      id: 'review',
      title: 'Проверка',
      body: 'Текст публикации',
      author: c.user!,
      status: 'changes_requested',
      aiReview: const {
        'status': 'changes_requested',
        'reason': 'Уберите запрос чужих банковских паролей.',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiReviewPanel(
            controller: c,
            post: post,
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.text('ИИ предлагает исправления'), findsOneWidget);
    expect(find.text('Исправить публикацию'), findsOneWidget);
    expect(find.text('Запросить проверку человеком'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
