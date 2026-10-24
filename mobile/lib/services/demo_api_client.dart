import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// An explicitly local demo. No request is delegated to the HTTP implementation.
class DemoApiClient extends ApiClient {
  DemoApiClient({Map<String, dynamic>? seed})
    : _seed = seed,
      super(baseUrl: 'demo://local');

  static const storageKey = 'pulse_offline_demo_v1';
  final Map<String, dynamic>? _seed;
  Map<String, dynamic> _data = {};
  SharedPreferences? _preferences;
  Future<void>? _boot;
  @override
  bool get isOffline => true;

  Future<void> _load() => _boot ??= _loadOnce();
  Future<void> _loadOnce() async {
    _preferences = await SharedPreferences.getInstance();
    final saved = _preferences!.getString(storageKey);
    if (saved != null) {
      try {
        _data = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      } catch (_) {
        _data = {};
      }
    }
    if (_data['users'] is! List || (_data['users'] as List).isEmpty) {
      _data = Map<String, dynamic>.from(
        jsonDecode(
              _seed == null
                  ? await rootBundle.loadString('assets/demo/seed.json')
                  : jsonEncode(_seed),
            )
            as Map,
      );
      final generated = DateTime.tryParse(
        _data['generated_at']?.toString() ?? '',
      );
      final shift = generated == null
          ? Duration.zero
          : DateTime.now().toUtc().difference(generated);
      for (final value in _data.values.whereType<List>()) {
        for (final row in value.whereType<Map>()) {
          for (final key in [
            'created_at',
            'updated_at',
            'published_at',
            'event_start',
            'event_end',
            'accepted_at',
            'read_at',
          ]) {
            final date = DateTime.tryParse(row[key]?.toString() ?? '');
            if (date != null) {
              row[key] = date.add(shift).toUtc().toIso8601String();
            }
          }
        }
      }
      _data['generated_at'] = _now;
    }
    for (final table in [
      'users',
      'categories',
      'posts',
      'follows',
      'friendships',
      'bookmarks',
      'reactions',
      'attendance',
      'comments',
      'moderation_history',
      'comment_reports',
      'notifications',
      'conversations',
      'messages',
    ]) {
      _data.putIfAbsent(table, () => <dynamic>[]);
    }
    _data.putIfAbsent('review_onboarding', () => <dynamic>[]);
    if (_data['gallery_demo_version'] != 1) {
      final template =
          _seed ??
          Map<String, dynamic>.from(
            jsonDecode(await rootBundle.loadString('assets/demo/seed.json'))
                as Map,
          );
      for (final example in (template['posts'] as List).whereType<Map>()) {
        final images = example['image_urls'];
        if (images is! List || images.length < 2) continue;
        final existing = _rows('posts')
            .where(
              (row) =>
                  _eq(row['id'], example['id']) &&
                  row['title'] == example['title'] &&
                  row['cover_url'] == example['cover_url'],
            )
            .firstOrNull;
        if (existing != null &&
            (existing['image_urls'] is! List ||
                (existing['image_urls'] as List).length < 2)) {
          existing['image_urls'] = [...images];
        }
      }
      _data['gallery_demo_version'] = 1;
    }
    for (final user in _rows('users')) {
      if (user['email'].toString().endsWith('@pulse.local')) {
        const label = 'Демонстрационный профиль для показа приложения.';
        if (!user['bio'].toString().contains(label)) {
          user['bio'] = '${user['bio'] ?? ''}\n\n$label'.trim();
        }
      } else {
        _onboardReviewUser(user);
      }
    }
    await _persist();
  }

  void _onboardReviewUser(Map<String, dynamic> user) {
    final id = _int(user['id']);
    final completed = _data['review_onboarding'] as List;
    if (completed.any((value) => _eq(value, id))) return;
    final now = DateTime.now().toUtc();
    final created = now.subtract(const Duration(minutes: 12)).toIso8601String();
    const contacts = {
      'timur@pulse.local':
          'Привет! На вечер кода можно прийти без опыта разработки. Если соберёшься, отметь участие в событии.',
      'artem@pulse.local':
          'Привет! На открытую тренировку можно прийти без команды. Напиши, если понадобятся подробности.',
    };
    for (final contact in contacts.entries) {
      final peer = _rows(
        'users',
      ).where((row) => row['email'] == contact.key).firstOrNull;
      if (peer == null) continue;
      final peerId = _int(peer['id']);
      final low = id < peerId ? id : peerId;
      final high = id > peerId ? id : peerId;
      final relation = _rows('friendships')
          .where(
            (row) => _eq(row['user_low'], low) && _eq(row['user_high'], high),
          )
          .firstOrNull;
      if (relation == null) {
        _rows('friendships').add({
          'user_low': low,
          'user_high': high,
          'requester_id': peerId,
          'created_at': created,
          'accepted_at': created,
        });
      } else {
        relation['accepted_at'] ??= created;
      }
      if (!_rows('follows').any(
        (row) =>
            _eq(row['follower_id'], id) && _eq(row['following_id'], peerId),
      )) {
        _rows('follows').add({'follower_id': id, 'following_id': peerId});
      }
      var chat = _rows('conversations')
          .where(
            (row) => _eq(row['user_low'], low) && _eq(row['user_high'], high),
          )
          .firstOrNull;
      if (chat == null) {
        chat = {
          'id': _next('conversations'),
          'user_low': low,
          'user_high': high,
          'created_at': created,
        };
        _rows('conversations').add(chat);
      }
      if (_rows(
        'messages',
      ).any((row) => _eq(row['conversation_id'], chat!['id']))) {
        continue;
      }
      _rows('messages').add({
        'id': _next('messages'),
        'conversation_id': chat['id'],
        'sender_id': peerId,
        'body': contact.value,
        'image_url': null,
        'created_at': created,
        'read_at': null,
      });
      if (contact.key == 'timur@pulse.local') {
        _rows('messages').add({
          'id': _next('messages'),
          'conversation_id': chat['id'],
          'sender_id': peerId,
          'body': 'Фотография с прошлой встречи.',
          'image_url': 'assets/demo/coding.jpg',
          'created_at': now
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
          'read_at': null,
        });
      }
    }
    final applicant = _rows(
      'users',
    ).where((row) => row['email'] == 'daria@pulse.local').firstOrNull;
    if (applicant != null) {
      final peerId = _int(applicant['id']);
      final low = id < peerId ? id : peerId;
      final high = id > peerId ? id : peerId;
      if (!_rows('friendships').any(
        (row) => _eq(row['user_low'], low) && _eq(row['user_high'], high),
      )) {
        _rows('friendships').add({
          'user_low': low,
          'user_high': high,
          'requester_id': peerId,
          'created_at': _now,
          'accepted_at': null,
        });
      }
    }
    completed.add(id);
  }

  Future<void> _persist() async =>
      _preferences!.setString(storageKey, jsonEncode(_data));
  List<Map<String, dynamic>> _rows(String table) =>
      (_data[table] as List).cast<Map<String, dynamic>>();
  bool _eq(dynamic first, dynamic second) =>
      first?.toString() == second?.toString();
  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  String get _now => DateTime.now().toUtc().toIso8601String();
  DateTime _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  int _next(String table) =>
      _rows(table).fold<int>(
        0,
        (max, row) => _int(row['id']) > max ? _int(row['id']) : max,
      ) +
      1;
  Map<String, dynamic> _row(String table, dynamic id) =>
      _rows(table).firstWhere(
        (row) => _eq(row['id'], id),
        orElse: () =>
            throw const ApiException('Материал не найден.', statusCode: 404),
      );
  int? get _viewerId => token?.startsWith('demo-') == true
      ? int.tryParse(token!.substring(5))
      : null;
  Map<String, dynamic> _require({bool moderator = false}) {
    if (_viewerId == null) {
      throw const ApiException('Войдите в демо-профиль.', statusCode: 401);
    }
    final user = _row('users', _viewerId);
    if (moderator && user['role'] != 'moderator') {
      throw const ApiException(
        'Этот раздел доступен модератору.',
        statusCode: 403,
      );
    }
    return user;
  }

  Map<String, dynamic>? _friendship(dynamic other) {
    if (_viewerId == null) return null;
    return _rows('friendships')
        .where(
          (row) =>
              (_eq(row['user_low'], _viewerId) &&
                  _eq(row['user_high'], other)) ||
              (_eq(row['user_high'], _viewerId) && _eq(row['user_low'], other)),
        )
        .firstOrNull;
  }

  Set<int> _friends() => _viewerId == null
      ? {}
      : _rows('friendships')
            .where(
              (row) =>
                  row['accepted_at'] != null &&
                  (_eq(row['user_low'], _viewerId) ||
                      _eq(row['user_high'], _viewerId)),
            )
            .map(
              (row) => _int(
                _eq(row['user_low'], _viewerId)
                    ? row['user_high']
                    : row['user_low'],
              ),
            )
            .toSet();
  Map<String, dynamic> _profile(Map<String, dynamic> source) {
    final id = source['id'];
    final relation = _friendship(id);
    return {
      for (final key in [
        'id',
        'name',
        'handle',
        'faculty',
        'course',
        'bio',
        'avatar_url',
        'avatar_color',
        'role',
        'interests',
      ])
        key: source[key],
      'email': _eq(id, _viewerId) ? source['email'] : '',
      'followers_count': _rows(
        'follows',
      ).where((r) => _eq(r['following_id'], id)).length,
      'following_count': _rows(
        'follows',
      ).where((r) => _eq(r['follower_id'], id)).length,
      'friends_count': _rows('friendships')
          .where(
            (r) =>
                r['accepted_at'] != null &&
                (_eq(r['user_low'], id) || _eq(r['user_high'], id)),
          )
          .length,
      'publications_count': _rows('posts')
          .where((r) => _eq(r['author_id'], id) && r['status'] == 'published')
          .length,
      'is_following': _rows('follows').any(
        (r) => _eq(r['follower_id'], _viewerId) && _eq(r['following_id'], id),
      ),
      'friendship_status': relation == null
          ? 'none'
          : relation['accepted_at'] != null
          ? 'friends'
          : _eq(relation['requester_id'], _viewerId)
          ? 'outgoing'
          : 'incoming',
    };
  }

  Map<String, dynamic> _article(Map<String, dynamic> row) {
    final id = row['id'];
    final reactions = {'like': 0, 'fire': 0, 'heart': 0, 'clap': 0};
    for (final reaction in _rows(
      'reactions',
    ).where((r) => _eq(r['post_id'], id))) {
      final key = reaction['reaction'].toString();
      reactions[key] = (reactions[key] ?? 0) + 1;
    }
    final attendees = _rows(
      'attendance',
    ).where((r) => _eq(r['post_id'], id)).toList();
    final friends = _friends();
    final friendAttendees = attendees
        .where((r) => friends.contains(_int(r['user_id'])))
        .map((r) => _profile(_row('users', r['user_id'])))
        .toList();
    final body = row['body']?.toString() ?? '';
    return {
      ...row,
      'image_urls': row['image_urls'] is List
          ? row['image_urls']
          : row['cover_url'] != null
          ? [row['cover_url']]
          : <String>[],
      'author': _profile(_row('users', row['author_id'])),
      'category': _row('categories', row['category']),
      'excerpt': body.length > 180 ? '${body.substring(0, 180)}…' : body,
      'reactions': reactions,
      'my_reaction': _rows('reactions')
          .where((r) => _eq(r['post_id'], id) && _eq(r['user_id'], _viewerId))
          .firstOrNull?['reaction'],
      'comments_count': _rows(
        'comments',
      ).where((r) => _eq(r['post_id'], id)).length,
      'is_bookmarked': _rows(
        'bookmarks',
      ).any((r) => _eq(r['post_id'], id) && _eq(r['user_id'], _viewerId)),
      'is_attending': attendees.any((r) => _eq(r['user_id'], _viewerId)),
      'attendees_count': attendees.length,
      'friend_attendees': friendAttendees,
      'friends_attending_count': friendAttendees.length,
    };
  }

  Map<String, dynamic> _post(dynamic id, {bool publicOnly = false}) {
    final post = _row('posts', id);
    if (post['status'] != 'published' &&
        (publicOnly ||
            _viewerId == null ||
            (!_eq(post['author_id'], _viewerId) &&
                _require()['role'] != 'moderator'))) {
      throw const ApiException('Публикация не найдена.', statusCode: 404);
    }
    return post;
  }

  Map<String, dynamic> _comment(Map<String, dynamic> row) => {
    ...row,
    'author': _profile(_row('users', row['author_id'])),
  };
  Map<String, dynamic> _page(List<dynamic> items, Map<String, dynamic> query) {
    final page = _int(query['page']).clamp(1, 10000);
    final size = _int(query['page_size']).clamp(1, 100);
    return {
      'items': items.skip((page - 1) * size).take(size).toList(),
      'total': items.length,
      'page': page,
      'page_size': size,
    };
  }

  Map<String, dynamic> _session(Map<String, dynamic> user) {
    token = 'demo-${user['id']}';
    return {'token': token, 'user': _profile(user)};
  }

  String _password(String email, String password) => sha256
      .convert(utf8.encode('pulse-local-demo:$email:$password'))
      .toString();
  void _history(dynamic postId, String decision, [String? reason]) =>
      _rows('moderation_history').add({
        'id': _next('moderation_history'),
        'post_id': _int(postId),
        'actor_id': _viewerId,
        'decision': decision,
        'reason': reason,
        'created_at': _now,
      });
  void _validatePost(Map<String, dynamic> post) {
    if ((post['title']?.toString().trim().length ?? 0) < 5) {
      throw const ApiException('Заголовок: минимум 5 символов.');
    }
    if ((post['body']?.toString().trim().length ?? 0) < 20) {
      throw const ApiException('Текст: минимум 20 символов.');
    }
    _row('categories', post['category']);
    if (post['type'] == 'event' &&
        (post['event_start'] == null ||
            (post['location']?.toString().trim().isEmpty ?? true))) {
      throw const ApiException('Укажите время и место мероприятия.');
    }
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    await _load();
    final result = _dispatch(method, path, body ?? {}, {
      'page': 1,
      'page_size': 100,
      ...?query,
    });
    if (method != 'GET') await _persist();
    return result;
  }

  dynamic _dispatch(
    String method,
    String path,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
  ) {
    final p = path.split('/').where((s) => s.isNotEmpty).toList();
    if (path == '/health') {
      return {'status': 'ok', 'service': 'pulse-offline-demo', 'demo': true};
    }
    if (path == '/categories') return _rows('categories');
    if (p.length == 3 && p[0] == 'categories' && p[2] == 'follow') {
      _row('categories', p[1]);
      final user = _require();
      final topics = (user['interests'] as List)
          .map((value) => value.toString())
          .toSet();
      if (method == 'PUT') {
        topics.add(p[1]);
      } else if (method == 'DELETE') {
        topics.remove(p[1]);
      }
      user['interests'] = topics.toList();
      return _profile(user);
    }
    if (path == '/auth/login') {
      final email = body['email'].toString().trim().toLowerCase();
      final user = _rows(
        'users',
      ).where((r) => r['email'].toString().toLowerCase() == email).firstOrNull;
      final password = body['password']?.toString() ?? '';
      final valid =
          user != null &&
          (user['demo_password_digest'] != null
              ? user['demo_password_digest'] == _password(email, password)
              : password ==
                    (user['role'] == 'moderator'
                        ? 'Moderator123!'
                        : 'Student123!'));
      if (!valid) {
        throw const ApiException(
          'Неверная почта или пароль демо-профиля.',
          statusCode: 401,
        );
      }
      return _session(user);
    }
    if (path == '/auth/register') {
      final email = body['email'].toString().trim().toLowerCase();
      if (_rows('users').any((r) => r['email'] == email)) {
        throw const ApiException('Такой демо-профиль уже есть.');
      }
      if (!email.contains('@') ||
          (body['password']?.toString().length ?? 0) < 8) {
        throw const ApiException('Укажите почту и пароль от 8 символов.');
      }
      final id = _next('users');
      final user = <String, dynamic>{
        'id': id,
        'email': email,
        'name': body['name'],
        'handle': 'student_$id',
        'role': 'student',
        'faculty': body['faculty'] ?? '',
        'course': body['course'],
        'bio': '',
        'avatar_url': null,
        'avatar_color': '#3459E6',
        'interests': <String>[],
        'created_at': _now,
        'demo_password_digest': _password(email, body['password'].toString()),
      };
      _rows('users').add(user);
      _onboardReviewUser(user);
      return _session(user);
    }
    if (path == '/auth/logout') {
      token = null;
      return {'ok': true};
    }
    if (path == '/me') {
      final user = _require();
      if (method == 'PATCH') {
        for (final key in [
          'name',
          'handle',
          'faculty',
          'course',
          'bio',
          'avatar_url',
          'avatar_color',
          'interests',
        ]) {
          if (body.containsKey(key)) user[key] = body[key];
        }
      }
      return _profile(user);
    }
    if (path == '/users') {
      final search = query['search']?.toString().toLowerCase() ?? '';
      return _page(
        _rows('users')
            .where(
              (r) => '${r['name']} ${r['handle']} ${r['faculty']}'
                  .toLowerCase()
                  .contains(search),
            )
            .map(_profile)
            .toList(),
        query,
      );
    }
    if (p.firstOrNull == 'users' && p.length >= 2) {
      final target = _row('users', p[1]);
      if (p.length == 2) return _profile(target);
      if (p[2] == 'posts') {
        return _page(
          _rows('posts')
              .where(
                (r) => _eq(r['author_id'], p[1]) && r['status'] == 'published',
              )
              .map(_article)
              .toList(),
          query,
        );
      }
      _require();
      if (p[2] == 'follow') {
        _rows('follows').removeWhere(
          (r) =>
              _eq(r['follower_id'], _viewerId) && _eq(r['following_id'], p[1]),
        );
        if (method == 'PUT' && !_eq(p[1], _viewerId)) {
          _rows(
            'follows',
          ).add({'follower_id': _viewerId, 'following_id': _int(p[1])});
        }
      } else if (p[2] == 'friendship') {
        final relation = _friendship(p[1]);
        if (relation != null) _rows('friendships').remove(relation);
      } else if (p[2] == 'friend-request') {
        if (_eq(p[1], _viewerId)) {
          throw const ApiException('Выберите другой профиль.');
        }
        final relation = _friendship(p[1]);
        if (p.length == 4) {
          if (relation == null || _eq(relation['requester_id'], _viewerId)) {
            throw const ApiException('Входящая заявка не найдена.');
          }
          relation['accepted_at'] = _now;
        } else if (relation == null) {
          final targetId = _int(p[1]);
          _rows('friendships').add({
            'user_low': _viewerId! < targetId ? _viewerId : targetId,
            'user_high': _viewerId! > targetId ? _viewerId : targetId,
            'requester_id': _viewerId,
            'created_at': _now,
            'accepted_at': null,
          });
        }
      }
      return _profile(target);
    }
    if (path == '/friends') {
      _require();
      return _page(
        _friends().map((id) => _profile(_row('users', id))).toList(),
        query,
      );
    }
    if (path == '/friends/requests') {
      _require();
      final pending = _rows('friendships').where(
        (r) =>
            r['accepted_at'] == null &&
            (_eq(r['user_low'], _viewerId) || _eq(r['user_high'], _viewerId)),
      );
      List<dynamic> requests(bool outgoing) => pending
          .where((r) => _eq(r['requester_id'], _viewerId) == outgoing)
          .map(
            (r) => _profile(
              _row(
                'users',
                _eq(r['user_low'], _viewerId) ? r['user_high'] : r['user_low'],
              ),
            ),
          )
          .toList();
      return {'incoming': requests(false), 'outgoing': requests(true)};
    }
    if (path == '/posts' && method == 'GET') {
      var posts = _rows('posts').where((r) => r['status'] == 'published');
      if (query['category'] != null) {
        posts = posts.where((r) => r['category'] == query['category']);
      }
      if (query['type'] != null) {
        posts = posts.where((r) => r['type'] == query['type']);
      }
      final search = query['search']?.toString().toLowerCase() ?? '';
      if (search.isNotEmpty) {
        posts = posts.where(
          (r) => '${r['title']} ${r['body']}'.toLowerCase().contains(search),
        );
      }
      if (query['feed'] != null || query['saved'] == true) _require();
      if (query['feed'] == 'following') {
        posts = posts.where(
          (r) =>
              (_require()['interests'] as List).contains(r['category']) ||
              _rows('follows').any(
                (f) =>
                    _eq(f['follower_id'], _viewerId) &&
                    _eq(f['following_id'], r['author_id']),
              ),
        );
      }
      if (query['feed'] == 'interests' &&
          (_require()['interests'] as List).isNotEmpty) {
        posts = posts.where(
          (r) => (_require()['interests'] as List).contains(r['category']),
        );
      }
      if (query['feed'] == 'friends') {
        posts = posts.where(
          (r) =>
              r['type'] == 'event' &&
              _date(r['event_start']).isAfter(DateTime.now()) &&
              _article(r)['friends_attending_count'] > 0,
        );
      }
      if (query['saved'] == true) {
        posts = posts.where(
          (r) => _rows('bookmarks').any(
            (b) => _eq(b['user_id'], _viewerId) && _eq(b['post_id'], r['id']),
          ),
        );
      }
      if (query['free'] == true) {
        posts = posts.where(
          (r) =>
              r['type'] == 'event' &&
              [null, '', '0', 'Бесплатно'].contains(r['price']),
        );
      }
      if (query['period'] != null) {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(
          Duration(days: query['period'] == 'today' ? 1 : 7),
        );
        posts = posts.where(
          (r) =>
              r['type'] == 'event' &&
              !_date(r['event_start']).isBefore(start) &&
              _date(r['event_start']).isBefore(end),
        );
      }
      final sorted = posts.toList()
        ..sort(
          (a, b) => _date(
            b['published_at'] ?? b['created_at'],
          ).compareTo(_date(a['published_at'] ?? a['created_at'])),
        );
      return _page(sorted.map(_article).toList(), query);
    }
    if (path == '/posts' && method == 'POST') {
      _require();
      _validatePost(body);
      final row = <String, dynamic>{
        'id': _next('posts'),
        'author_id': _viewerId,
        'type': 'news',
        'cover_url': null,
        'event_start': null,
        'event_end': null,
        'location': null,
        'price': null,
        'registration_url': null,
        ...body,
        'status': body['submit'] == false ? 'draft' : 'pending',
        'moderation_reason': null,
        'created_at': _now,
        'updated_at': _now,
        'published_at': null,
      };
      row.remove('submit');
      if (body['image_urls'] is List) {
        final images = (body['image_urls'] as List).take(6).toList();
        row['image_urls'] = images;
        row['cover_url'] = images.firstOrNull;
      }
      _rows('posts').add(row);
      if (row['status'] == 'pending') _history(row['id'], 'submitted');
      return _article(row);
    }
    if (path == '/me/posts') {
      _require();
      return _page(
        _rows('posts')
            .where((r) => _eq(r['author_id'], _viewerId))
            .toList()
            .reversed
            .map(_article)
            .toList(),
        query,
      );
    }
    if (p.firstOrNull == 'posts' && p.length >= 2) {
      final post = _post(p[1]);
      if (p.length == 2) {
        if (method == 'PATCH') {
          _require();
          if (!_eq(post['author_id'], _viewerId)) {
            throw const ApiException('Редактировать может только автор.');
          }
          final updated = {...post, ...body};
          _validatePost(updated);
          post.addAll(body);
          if (body['image_urls'] is List) {
            final images = (body['image_urls'] as List).take(6).toList();
            post['image_urls'] = images;
            post['cover_url'] = images.firstOrNull;
          }
          post.remove('submit');
          post.addAll({
            'status': body['submit'] == true ? 'pending' : 'draft',
            'moderation_reason': null,
            'published_at': null,
            'updated_at': _now,
          });
          _history(post['id'], 'edited');
        }
        return _article(post);
      }
      final action = p[2];
      if (action == 'comments' && method == 'GET') {
        return _page(
          _rows(
            'comments',
          ).where((r) => _eq(r['post_id'], post['id'])).map(_comment).toList(),
          query,
        );
      }
      _require();
      if (action == 'submit') {
        if (!_eq(post['author_id'], _viewerId)) {
          throw const ApiException('Отправить материал может только автор.');
        }
        _validatePost(post);
        post.addAll({
          'status': 'pending',
          'moderation_reason': null,
          'updated_at': _now,
        });
        _history(post['id'], 'submitted');
      } else if (action == 'comments') {
        _post(p[1], publicOnly: true);
        final text = body['body']?.toString().trim() ?? '';
        if (text.isEmpty) throw const ApiException('Напишите комментарий.');
        final comment = <String, dynamic>{
          'id': _next('comments'),
          'post_id': post['id'],
          'author_id': _viewerId,
          'body': text,
          'parent_id': body['parent_id'] == null
              ? null
              : _int(body['parent_id']),
          'created_at': _now,
        };
        _rows('comments').add(comment);
        return _comment(comment);
      } else if (['bookmark', 'reaction', 'attendance'].contains(action)) {
        final table = {
          'bookmark': 'bookmarks',
          'reaction': 'reactions',
          'attendance': 'attendance',
        }[action]!;
        _rows(table).removeWhere(
          (r) => _eq(r['user_id'], _viewerId) && _eq(r['post_id'], post['id']),
        );
        if (method == 'PUT') {
          _rows(table).add({
            'user_id': _viewerId,
            'post_id': post['id'],
            if (action == 'reaction') 'reaction': body['reaction'],
          });
        }
      }
      return _article(post);
    }
    if (p.firstOrNull == 'comments' && p.length >= 2) {
      final user = _require();
      final comment = _row('comments', p[1]);
      if (p.length == 3) {
        _rows('comment_reports').add({
          'id': _next('comment_reports'),
          'comment_id': comment['id'],
          'user_id': _viewerId,
          'reason': body['reason'],
          'status': 'open',
          'created_at': _now,
        });
      } else {
        if (!_eq(comment['author_id'], _viewerId) &&
            user['role'] != 'moderator') {
          throw const ApiException(
            'Удалять чужие комментарии может модератор.',
          );
        }
        final ids = <int>{_int(comment['id'])};
        var changed = true;
        while (changed) {
          final count = ids.length;
          ids.addAll(
            _rows('comments')
                .where((r) => ids.contains(_int(r['parent_id'])))
                .map((r) => _int(r['id'])),
          );
          changed = count != ids.length;
        }
        _rows('comments').removeWhere((r) => ids.contains(_int(r['id'])));
        _rows(
          'comment_reports',
        ).removeWhere((r) => ids.contains(_int(r['comment_id'])));
      }
      return {'ok': true};
    }
    if (p.firstOrNull == 'moderation') {
      _require(
        moderator:
            path != '/moderation/posts/${p.length > 2 ? p[2] : ''}/history',
      );
      if (path == '/moderation/posts') {
        return _page(
          _rows('posts')
              .where((r) => r['status'] == (query['status'] ?? 'pending'))
              .map(_article)
              .toList(),
          query,
        );
      }
      if (p.length == 4 && p[1] == 'posts') {
        final post = _post(p[2]);
        if (p[3] == 'history') {
          if (!_eq(post['author_id'], _viewerId) &&
              _require()['role'] != 'moderator') {
            throw const ApiException('История доступна автору и модератору.');
          }
          return {
            'items': _rows('moderation_history')
                .where((r) => _eq(r['post_id'], p[2]))
                .map(
                  (r) => {
                    ...r,
                    'action':
                        {
                          'publish': 'approve',
                          'changes_requested': 'return',
                        }[r['decision']] ??
                        r['decision'],
                    'moderator': _profile(_row('users', r['actor_id'])),
                  },
                )
                .toList(),
          };
        }
        if (post['status'] != 'pending' ||
            post['updated_at'] != body['expected_updated_at']) {
          throw const ApiException(
            'Материал изменился. Обновите экран.',
            statusCode: 409,
          );
        }
        if (_eq(post['author_id'], _viewerId)) {
          throw const ApiException(
            'Ваш материал должен проверить другой модератор.',
          );
        }
        final decision = body['decision'];
        final reason = body['reason']?.toString().trim() ?? '';
        if (decision != 'publish' && reason.length < 3) {
          throw const ApiException('Укажите причину решения.');
        }
        post.addAll({
          'status': {
            'publish': 'published',
            'changes_requested': 'changes_requested',
            'reject': 'rejected',
          }[decision],
          'moderation_reason': reason,
          'updated_at': _now,
          'published_at': decision == 'publish' ? _now : null,
        });
        _history(post['id'], decision, reason);
        return _article(post);
      }
      if (path == '/moderation/reports') {
        return _page(
          _rows('comment_reports')
              .where((r) => r['status'] == 'open')
              .map(
                (r) => {
                  ...r,
                  'comment': _comment(_row('comments', r['comment_id'])),
                  'reporter': _profile(_row('users', r['user_id'])),
                },
              )
              .toList(),
          query,
        );
      }
      if (p.length == 4 && p[1] == 'reports') {
        _row('comment_reports', p[2])['status'] = 'resolved';
        return {'ok': true};
      }
    }
    if (p.firstOrNull == 'chats') return _dispatchChat(method, p, body, query);
    if (path == '/notifications') {
      _require();
      return _page(
        _rows(
          'notifications',
        ).where((r) => _eq(r['user_id'], _viewerId)).toList(),
        query,
      );
    }
    throw const ApiException('Раздел недоступен в демо-версии.');
  }

  Map<String, dynamic> _chat(Map<String, dynamic> row) {
    final peer = _eq(row['user_low'], _viewerId)
        ? row['user_high']
        : row['user_low'];
    final messages =
        _rows(
            'messages',
          ).where((r) => _eq(r['conversation_id'], row['id'])).toList()
          ..sort((a, b) => _int(a['id']).compareTo(_int(b['id'])));
    return {
      ...row,
      'peer': _profile(_row('users', peer)),
      'can_send': _friends().contains(_int(peer)),
      'last_message': messages.lastOrNull,
      'unread_count': messages
          .where((r) => !_eq(r['sender_id'], _viewerId) && r['read_at'] == null)
          .length,
    };
  }

  dynamic _dispatchChat(
    String method,
    List<String> path,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
  ) {
    _require();
    if (path.length == 1) {
      if (method == 'GET') {
        return _page(
          _rows('conversations')
              .where(
                (r) =>
                    _eq(r['user_low'], _viewerId) ||
                    _eq(r['user_high'], _viewerId),
              )
              .map(_chat)
              .toList(),
          query,
        );
      }
      final other = _int(body['user_id']);
      if (other == _viewerId || !_friends().contains(other)) {
        throw const ApiException('Добавьте собеседника в друзья.');
      }
      final existing = _rows('conversations')
          .where(
            (r) =>
                (_eq(r['user_low'], _viewerId) && _eq(r['user_high'], other)) ||
                (_eq(r['user_high'], _viewerId) && _eq(r['user_low'], other)),
          )
          .firstOrNull;
      if (existing != null) return _chat(existing);
      final chat = <String, dynamic>{
        'id': _next('conversations'),
        'user_low': _viewerId! < other ? _viewerId : other,
        'user_high': _viewerId! > other ? _viewerId : other,
        'created_at': _now,
      };
      _rows('conversations').add(chat);
      return _chat(chat);
    }
    final chat = _row('conversations', path[1]);
    if (!_eq(chat['user_low'], _viewerId) &&
        !_eq(chat['user_high'], _viewerId)) {
      throw const ApiException('Переписка не найдена.', statusCode: 404);
    }
    if (path.length == 3 && path[2] == 'read') {
      for (final message in _rows('messages').where(
        (r) =>
            _eq(r['conversation_id'], chat['id']) &&
            !_eq(r['sender_id'], _viewerId),
      )) {
        message['read_at'] ??= _now;
      }
      return {'ok': true};
    }
    if (path.length == 3 && path[2] == 'messages') {
      if (method == 'GET') {
        var messages = _rows(
          'messages',
        ).where((r) => _eq(r['conversation_id'], chat['id']));
        if (query['after_id'] != null) {
          messages = messages.where(
            (r) => _int(r['id']) > _int(query['after_id']),
          );
        }
        if (query['before_id'] != null) {
          messages = messages.where(
            (r) => _int(r['id']) < _int(query['before_id']),
          );
        }
        final sorted = messages.toList()
          ..sort((a, b) => _int(a['id']).compareTo(_int(b['id'])));
        return {
          'items': sorted
              .skip((sorted.length - 100).clamp(0, sorted.length))
              .toList(),
          'total': sorted.length,
        };
      }
      if (_chat(chat)['can_send'] != true) {
        throw const ApiException('Добавьте собеседника в друзья.');
      }
      final text = body['body']?.toString().trim() ?? '';
      final image = body['image_url'];
      if (text.isEmpty && image == null) {
        throw const ApiException('Введите текст или выберите фотографию.');
      }
      final message = <String, dynamic>{
        'id': _next('messages'),
        'conversation_id': chat['id'],
        'sender_id': _viewerId,
        'body': text,
        'image_url': image,
        'created_at': _now,
        'read_at': null,
      };
      _rows('messages').add(message);
      return message;
    }
    throw const ApiException('Переписка не найдена.');
  }

  @override
  Future<String> upload(
    List<int> bytes,
    String filename, {
    String path = '/uploads',
  }) async {
    await _load();
    _require();
    if (bytes.length > 8 * 1024 * 1024) {
      throw const ApiException('Выберите фотографию до 8 МБ.');
    }
    final mime = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50
        ? 'image/png'
        : 'image/jpeg';
    return Uri.dataFromBytes(bytes, mimeType: mime).toString();
  }

  @override
  Future<Uint8List> downloadPrivateImage(String path) async {
    await _load();
    _require();
    if (path.startsWith('assets/demo/')) {
      return (await rootBundle.load(path)).buffer.asUint8List();
    }
    if (path.startsWith('data:image/')) {
      return Uint8List.fromList(Uri.parse(path).data!.contentAsBytes());
    }
    throw const ApiException('Фотография недоступна в демо.');
  }
}
