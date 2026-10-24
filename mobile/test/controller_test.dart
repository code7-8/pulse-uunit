import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/services/api_client.dart';
import 'package:pulse/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const demoUser = {'id': 1, 'name': 'Александр Соколов', 'role': 'student'};
Map<String, dynamic> post(
  String id, {
  String revision = '2026-10-23T12:00:00.123456Z',
}) => {
  'id': id,
  'title': 'Мероприятие в университете',
  'body': 'Обсуждаем новый проект и собираем команду.',
  'author': demoUser,
  'status': 'published',
  'updated_at': revision,
};
http.Response reply(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Refreshing after an offline startup also restores the categories',
    () async {
      SharedPreferences.setMockInitialValues({});
      var categoriesCalls = 0;
      final controller = AppController(
        api: ApiClient(
          baseUrl: 'https://test.example',
          client: MockClient((request) async {
            if (request.url.path == '/api/categories') {
              categoriesCalls++;
              return categoriesCalls == 1
                  ? reply({}, 503)
                  : reply([
                      {'id': 'campus', 'name': 'Кампус'},
                    ]);
            }
            return reply({
              'items': [post('1')],
            });
          }),
        ),
      );
      await controller.initialize();
      expect(controller.error, isNotNull);
      await controller.loadFeed();
      expect(controller.categories.single.name, 'Кампус');
      expect(controller.posts.single.id, '1');
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test('A delayed search cannot replace a more recent result', () async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'http://localhost:8000',
      client: MockClient((request) {
        return request.url.queryParameters['search'] == 'старый'
            ? first.future
            : second.future;
      }),
    );
    final controller = AppController(api: client);
    final older = controller.loadFeed(query: 'старый');
    final newer = controller.loadFeed(query: 'новый');
    second.complete(
      reply({
        'items': [post('2')],
      }),
    );
    await newer;
    first.complete(
      reply({
        'items': [post('1')],
      }),
    );
    await older;
    expect(controller.posts.single.id, '2');
    expect(controller.searchQuery, 'новый');
    expect(controller.loading, false);
    controller.dispose();
  });

  test(
    'Friends event feed transmits the event and friendship filters',
    () async {
      late Uri requested;
      final controller = AppController(
        api: ApiClient(
          baseUrl: 'http://localhost:8000',
          client: MockClient((request) async {
            requested = request.url;
            return reply({'items': []});
          }),
        ),
      );
      await controller.loadFeed(mode: 'friends', eventsOnly: true);
      expect(requested.queryParameters['type'], 'event');
      expect(requested.queryParameters['feed'], 'friends');
      controller.dispose();
    },
  );

  test(
    'Moderation echoes the exact reviewed revision and omits an empty reason',
    () async {
      Map<String, dynamic>? decision;
      final controller = AppController(
        api: ApiClient(
          baseUrl: 'http://localhost:8000',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/login')) {
              return reply({
                'token': 'local-test-session',
                'user': {...demoUser, 'role': 'moderator'},
              });
            }
            if (request.url.path.endsWith('/decision')) {
              decision = Map<String, dynamic>.from(
                jsonDecode(request.body) as Map,
              );
              return reply(post('7'));
            }
            if (request.url.path.endsWith('/posts/7')) return reply(post('7'));
            return reply({'items': []});
          }),
        ),
      );
      await controller.login('moderator@pulse.local', 'Moderator123!');
      await controller.loadPost('7');
      await controller.moderate('7', 'approve');
      expect(decision?['decision'], 'publish');
      expect(decision?['expected_updated_at'], '2026-10-23T12:00:00.123456Z');
      expect(decision?.containsKey('reason'), false);
      controller.dispose();
    },
  );

  test(
    'An unreachable replacement server receives no session token and does not replace the connection',
    () async {
      final headers = <String, Map<String, String>>{};
      final client = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          headers[request.url.host] = request.headers;
          if (request.url.host == 'unreachable.test') {
            return reply({'detail': 'Недоступно'}, 503);
          }
          if (request.url.path.endsWith('/auth/login')) {
            return reply({'token': 'local-test-session', 'user': demoUser});
          }
          return reply({'items': []});
        }),
      );
      final controller = AppController(api: client);
      await controller.login('student@pulse.local', 'Student123!');
      await expectLater(
        controller.setConnection('http://unreachable.test:8000'),
        throwsA(isA<ApiException>()),
      );
      expect(controller.baseUrl, 'http://localhost:8000');
      expect(controller.user?.id, '1');
      expect(
        headers['unreachable.test']?.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      await controller.loadFeed();
      expect(
        headers['localhost']?['Authorization'],
        'Bearer local-test-session',
      );
      controller.dispose();
    },
  );

  test(
    'Private image loading refuses arbitrary external destinations',
    () async {
      var requests = 0;
      final client = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          requests++;
          return reply({});
        }),
      );
      await expectLater(
        client.downloadPrivateImage('https://outside.test/photo.jpg'),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 0);
      client.close();
    },
  );

  test(
    'Server validation is displayed in Russian without losing UTF-8',
    () async {
      final client = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient(
          (request) async =>
              reply({'detail': 'Заголовок: минимум 5 символов'}, 422),
        ),
      );
      await expectLater(
        client.request('POST', '/posts', body: {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Заголовок: минимум 5 символов',
          ),
        ),
      );
      client.close();
    },
  );
}
