import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import '../services/api_client.dart';

class AppController extends PulseController {
  AppController({ApiClient? api})
    : _api = api ?? ApiClient.production(baseUrl: _defaultUrl);

  static const _defaultUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.31.245:8000',
  );
  static const _storage = FlutterSecureStorage();
  final ApiClient _api;
  SharedPreferences? _preferences;
  UserProfile? _user;
  List<CampusPost> _posts = [], _saved = [], _mine = [], _moderation = [];
  List<Category> _categories = [];
  final Map<String, CampusPost> _details = {};
  final Map<String, Future<Uint8List>> _chatImages = {};
  bool _loading = false;
  String? _error;
  String? _category;
  String _query = '', _mode = 'all';
  ThemeMode _theme = ThemeMode.light;
  Color _accent = const Color(0xFF4D19CC);
  int _feedGeneration = 0;
  bool _categoriesNeedRetry = false;

  @override
  UserProfile? get user => _user;
  @override
  List<CampusPost> get posts => List.unmodifiable(_posts);
  @override
  List<Category> get categories => List.unmodifiable(_categories);
  @override
  List<CampusPost> get savedPosts => List.unmodifiable(_saved);
  @override
  List<CampusPost> get myPosts => List.unmodifiable(_mine);
  @override
  List<CampusPost> get moderationPosts => List.unmodifiable(_moderation);
  @override
  bool get loading => _loading;
  @override
  String? get error => _error;
  @override
  String? get selectedCategory => _category;
  @override
  String get searchQuery => _query;
  @override
  String get feedMode => _mode;
  @override
  ThemeMode get themeMode => _theme;
  @override
  Color get accent => _accent;
  @override
  String get baseUrl => _api.baseUrl;
  @override
  bool get automaticConnection => _api.hasManagedEndpoint;

  Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);
  List<dynamic> _items(dynamic value) =>
      value is List ? value : (value as Map?)?['items'] as List? ?? [];
  List<CampusPost> _postList(dynamic value) =>
      _items(value).map((e) => CampusPost.fromJson(_map(e))).toList();
  String get _cacheKey => 'public_feed_${_api.sessionNamespace}';

  @override
  Future<void> initialize() async {
    _loading = true;
    notifyListeners();
    try {
      _preferences = await SharedPreferences.getInstance();
      if (_api.hasManagedEndpoint) {
        _api.baseUrl =
            _preferences!.getString(
              'managed_endpoint_${_api.sessionNamespace}',
            ) ??
            _api.baseUrl;
      } else if (!_api.isOffline) {
        final savedUrl = _preferences!.getString('api_base_url');
        final migrateLocalAddress =
            const bool.fromEnvironment('PUBLIC_BUILD') &&
            savedUrl != null &&
            savedUrl.startsWith('http://');
        if (!migrateLocalAddress) {
          _api.baseUrl = savedUrl ?? _api.baseUrl;
        }
        if (migrateLocalAddress) {
          await _preferences!.setString('api_base_url', _api.baseUrl);
        }
      }
      final theme = _preferences!.getString('theme');
      _theme = ThemeMode.values.firstWhere(
        (v) => v.name == theme,
        orElse: () => ThemeMode.light,
      );
      _accent = Color(_preferences!.getInt('accent') ?? 0xFF4D19CC);
      final cached = _preferences!.getString(_cacheKey);
      if (cached != null) {
        try {
          _posts = _postList(jsonDecode(cached));
        } catch (_) {
          /* Discard old cache. */
        }
      }
      try {
        _api.token = await _storage.read(
          key: 'session_${_api.sessionNamespace}',
        );
      } catch (_) {
        /* Sessions remain memory-only if secure storage is unavailable. */
      }
      if (_api.isOffline) _api.token ??= 'demo-1';
      if (_api.token != null) {
        try {
          _user = UserProfile.fromJson(_map(await _api.request('GET', '/me')));
        } on ApiException catch (e) {
          if (e.statusCode == 401) await _clearSession();
        }
      }
      dynamic categories;
      try {
        categories = await _api.request('GET', '/categories');
        _categoriesNeedRetry = false;
      } catch (_) {
        _categoriesNeedRetry = true;
        rethrow;
      }
      _categories = _items(
        categories,
      ).map((e) => Category.fromJson(_map(e))).toList();
      await loadFeed();
      if (_api.hasManagedEndpoint) {
        await _preferences!.setString(
          'managed_endpoint_${_api.sessionNamespace}',
          _api.baseUrl,
        );
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> loadFeed({
    String? categoryId,
    String? query,
    String? mode,
    bool eventsOnly = false,
  }) async {
    final generation = ++_feedGeneration;
    _category = categoryId;
    _query = query ?? _query;
    _mode = mode ?? _mode;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (_categoriesNeedRetry) {
        _categories = _items(
          await _api.request('GET', '/categories'),
        ).map((e) => Category.fromJson(_map(e))).toList();
        _categoriesNeedRetry = false;
      }
      final filters = <String, dynamic>{
        'category': _category,
        'search': _query,
        'page_size': 100,
        if (eventsOnly) 'type': 'event',
        if (_mode == 'following') 'feed': 'following',
        if (_mode == 'interests') 'feed': 'interests',
        if (_mode == 'friends') 'feed': 'friends',
        if (_mode == 'today' || _mode == 'week') 'period': _mode,
        if (_mode == 'free') 'free': true,
      };
      final data = await _api.request('GET', '/posts', query: filters);
      if (generation != _feedGeneration) return;
      _posts = _postList(data);
      if (_api.hasManagedEndpoint) {
        await _preferences?.setString(
          'managed_endpoint_${_api.sessionNamespace}',
          _api.baseUrl,
        );
      }
      for (final post in _posts) {
        _details[post.id] = post;
      }
      if (_mode == 'all' &&
          _category == null &&
          _query.isEmpty &&
          !eventsOnly) {
        await _preferences?.setString(_cacheKey, jsonEncode(data));
      }
    } catch (e) {
      if (generation != _feedGeneration) return;
      _error = e.toString();
      if (_posts.isEmpty) rethrow;
    } finally {
      if (generation == _feedGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _requireUser() {
    if (_user == null) {
      throw const ApiException(
        'Войдите в аккаунт, чтобы продолжить.',
        statusCode: 401,
      );
    }
  }

  Future<void> _saveSession(dynamic data) async {
    final map = _map(data);
    _api.token = map['token'] as String;
    _user = UserProfile.fromJson(_map(map['user']));
    try {
      await _storage.write(
        key: 'session_${_api.sessionNamespace}',
        value: _api.token,
      );
    } catch (_) {
      /* Current session still works. */
    }
    _saved = [];
    _mine = [];
    _moderation = [];
    _details.clear();
    _chatImages.clear();
    _commentReports.clear();
    _error = null;
    notifyListeners();
    try {
      await loadFeed(categoryId: _category, query: _query, mode: _mode);
    } catch (_) {
      /* Feed displays retry state. */
    }
  }

  @override
  Future<void> login(String email, String password) async => _saveSession(
    await _api.request(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    ),
  );
  Map<String, dynamic> _profileFields(Map<String, dynamic> fields) => {
    ...fields,
    if (fields.containsKey('course'))
      'course':
          fields['course'] == null || fields['course'].toString().trim().isEmpty
          ? null
          : int.tryParse(fields['course'].toString()),
  };
  @override
  Future<void> register(Map<String, dynamic> fields) async => _saveSession(
    await _api.request('POST', '/auth/register', body: _profileFields(fields)),
  );
  Future<void> _clearSession() async {
    try {
      await _storage.delete(key: 'session_${_api.sessionNamespace}');
    } catch (_) {
      /* No persisted session. */
    }
    _api.token = null;
    _user = null;
    _saved = [];
    _mine = [];
    _moderation = [];
    _details.clear();
    _chatImages.clear();
    _commentReports.clear();
  }

  @override
  Future<void> logout() async {
    try {
      await _api.request('POST', '/auth/logout');
    } catch (_) {
      /* Local logout must succeed offline. */
    }
    await _clearSession();
    _mode = 'all';
    notifyListeners();
    try {
      await loadFeed(mode: 'all');
    } catch (_) {
      /* Retry remains available. */
    }
  }

  void _replace(CampusPost post) {
    _details[post.id] = post;
    List<CampusPost> update(List<CampusPost> list) =>
        list.map((p) => p.id == post.id ? post : p).toList();
    _posts = update(_posts);
    _saved = update(_saved).where((p) => p.isBookmarked).toList();
    _mine = update(_mine);
    _moderation = update(_moderation);
    notifyListeners();
  }

  @override
  Future<CampusPost> loadPost(String id) async {
    final post = CampusPost.fromJson(
      _map(await _api.request('GET', '/posts/$id')),
    );
    _replace(post);
    return post;
  }

  @override
  Future<void> loadSavedPosts() async {
    _requireUser();
    _saved = _postList(
      await _api.request(
        'GET',
        '/posts',
        query: {'saved': true, 'page_size': 100},
      ),
    );
    notifyListeners();
  }

  @override
  Future<List<CampusComment>> loadComments(String postId) async => _items(
    await _api.request(
      'GET',
      '/posts/$postId/comments',
      query: {'page_size': 100},
    ),
  ).map((e) => CampusComment.fromJson(_map(e))).toList();
  @override
  Future<void> addComment(
    String postId,
    String body, {
    String? parentId,
  }) async {
    _requireUser();
    await _api.request(
      'POST',
      '/posts/$postId/comments',
      body: {'body': body.trim(), 'parent_id': ?parentId},
    );
    await loadPost(postId);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    _requireUser();
    await _api.request('DELETE', '/comments/$commentId');
  }

  @override
  Future<void> reportComment(String commentId, String reason) async {
    _requireUser();
    await _api.request(
      'POST',
      '/comments/$commentId/report',
      body: {'reason': reason},
    );
  }

  @override
  Future<void> react(String postId, String reaction) async {
    _requireUser();
    final current = _details[postId] ?? await loadPost(postId);
    if (current.myReaction == reaction) {
      await _api.request('DELETE', '/posts/$postId/reaction');
    } else {
      await _api.request(
        'PUT',
        '/posts/$postId/reaction',
        body: {'reaction': reaction},
      );
    }
    await loadPost(postId);
  }

  @override
  Future<void> bookmark(String postId) async {
    _requireUser();
    final post = _details[postId] ?? await loadPost(postId);
    await _api.request(
      post.isBookmarked ? 'DELETE' : 'PUT',
      '/posts/$postId/bookmark',
    );
    final updated = await loadPost(postId);
    if (updated.isBookmarked && !_saved.any((p) => p.id == postId)) {
      _saved.insert(0, updated);
    }
    notifyListeners();
  }

  @override
  Future<void> attend(String postId) async {
    _requireUser();
    final post = _details[postId] ?? await loadPost(postId);
    await _api.request(
      post.isAttending ? 'DELETE' : 'PUT',
      '/posts/$postId/attendance',
    );
    await loadPost(postId);
  }

  @override
  Future<void> follow(String userId) async {
    _requireUser();
    final profile = await getProfile(userId);
    await _api.request(
      profile.isFollowing ? 'DELETE' : 'PUT',
      '/users/$userId/follow',
    );
    _user = UserProfile.fromJson(_map(await _api.request('GET', '/me')));
    notifyListeners();
  }

  @override
  Future<UserProfile> getProfile(String userId) async =>
      UserProfile.fromJson(_map(await _api.request('GET', '/users/$userId')));
  @override
  Future<List<UserProfile>> lookupUsers(String query) async =>
      _items(
            await _api.request(
              'GET',
              '/users',
              query: {'search': query, 'page_size': 50},
            ),
          )
          .map((e) => UserProfile.fromJson(_map(e)))
          .where((u) => u.id != _user?.id)
          .toList();
  @override
  Future<List<UserProfile>> loadFriends() async {
    _requireUser();
    return _items(
      await _api.request('GET', '/friends', query: {'page_size': 100}),
    ).map((e) => UserProfile.fromJson(_map(e))).toList();
  }

  @override
  Future<Map<String, List<UserProfile>>> loadFriendRequests() async {
    _requireUser();
    final data = _map(await _api.request('GET', '/friends/requests'));
    return {
      'incoming': _items(
        data['incoming'],
      ).map((e) => UserProfile.fromJson(_map(e))).toList(),
      'outgoing': _items(
        data['outgoing'],
      ).map((e) => UserProfile.fromJson(_map(e))).toList(),
    };
  }

  Future<void> _refreshSelf() async {
    _user = UserProfile.fromJson(_map(await _api.request('GET', '/me')));
    notifyListeners();
  }

  @override
  Future<void> sendFriendRequest(String userId) async {
    _requireUser();
    await _api.request('PUT', '/users/$userId/friend-request');
    await _refreshSelf();
  }

  @override
  Future<void> acceptFriendRequest(String userId) async {
    _requireUser();
    await _api.request('POST', '/users/$userId/friend-request/accept');
    await _refreshSelf();
  }

  @override
  Future<void> removeFriendship(String userId) async {
    _requireUser();
    await _api.request('DELETE', '/users/$userId/friendship');
    await _refreshSelf();
  }

  @override
  Future<List<Map<String, dynamic>>> loadChats() async {
    _requireUser();
    return _items(await _api.request('GET', '/chats')).map(_map).toList();
  }

  @override
  Future<Map<String, dynamic>> openChat(String userId) async {
    _requireUser();
    return _map(
      await _api.request(
        'POST',
        '/chats',
        body: {'user_id': int.parse(userId)},
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> loadMessages(
    String chatId, {
    int? afterId,
    int? beforeId,
  }) async {
    _requireUser();
    return _items(
      await _api.request(
        'GET',
        '/chats/$chatId/messages',
        query: {'after_id': afterId, 'before_id': beforeId, 'page_size': 100},
      ),
    ).map(_map).toList();
  }

  @override
  Future<Map<String, dynamic>> sendMessage(
    String chatId,
    String body, {
    String? imageUrl,
  }) async {
    _requireUser();
    return _map(
      await _api.request(
        'POST',
        '/chats/$chatId/messages',
        body: {'body': body.trim(), 'image_url': ?imageUrl},
      ),
    );
  }

  @override
  Future<void> markChatRead(String chatId) async {
    _requireUser();
    await _api.request('PUT', '/chats/$chatId/read');
  }

  @override
  Future<String?> pickAndUploadChatImage(String chatId) async {
    _requireUser();
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw const ApiException('Выберите фотографию размером до 8 МБ.');
    }
    return _api.upload(bytes, image.name, path: '/chats/$chatId/images');
  }

  @override
  Future<Uint8List> loadChatImage(String url) {
    _requireUser();
    if (_chatImages.length > 80) _chatImages.clear();
    return _chatImages.putIfAbsent(
      url,
      () => _api.downloadPrivateImage(url).catchError((Object error) {
        _chatImages.remove(url);
        throw error;
      }),
    );
  }

  final Map<String, Map<String, dynamic>> _commentReports = {};
  @override
  Future<List<Map<String, dynamic>>> loadCommentReports() async {
    _requireUser();
    final reports = _items(
      await _api.request(
        'GET',
        '/moderation/reports',
        query: {'page_size': 50},
      ),
    ).map(_map).toList();
    for (final report in reports) {
      _commentReports[report['id'].toString()] = report;
    }
    return reports;
  }

  @override
  Future<void> resolveCommentReport(String reportId, String action) async {
    _requireUser();
    if (action == 'delete_comment') {
      final report = _commentReports[reportId];
      if (report == null) throw const ApiException('Обновите список жалоб.');
      await _api.request(
        'DELETE',
        '/comments/${(report['comment'] as Map)['id']}',
      );
    } else {
      await _api.request('POST', '/moderation/reports/$reportId/resolve');
    }
    _commentReports.remove(reportId);
  }

  @override
  Future<List<CampusPost>> getUserPosts(String userId) async => _postList(
    await _api.request(
      'GET',
      '/users/$userId/posts',
      query: {'page_size': 100},
    ),
  );
  @override
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    _requireUser();
    _user = UserProfile.fromJson(
      _map(await _api.request('PATCH', '/me', body: _profileFields(fields))),
    );
    notifyListeners();
  }

  Map<String, dynamic> _postFields(Map<String, dynamic> fields) => {
    ...fields,
    if (fields['category'] is Category)
      'category': (fields['category'] as Category).id,
    if (fields['event_start'] is DateTime)
      'event_start': (fields['event_start'] as DateTime)
          .toUtc()
          .toIso8601String(),
    if (fields['event_end'] is DateTime)
      'event_end': (fields['event_end'] as DateTime).toUtc().toIso8601String(),
    if (fields['event_start'] is String &&
        (fields['event_start'] as String).isNotEmpty)
      'event_start': DateTime.parse(
        fields['event_start'] as String,
      ).toUtc().toIso8601String(),
    if (fields['event_end'] is String &&
        (fields['event_end'] as String).isNotEmpty)
      'event_end': DateTime.parse(
        fields['event_end'] as String,
      ).toUtc().toIso8601String(),
  };
  @override
  Future<CampusPost> createPost(Map<String, dynamic> fields) async {
    _requireUser();
    final post = CampusPost.fromJson(
      _map(await _api.request('POST', '/posts', body: _postFields(fields))),
    );
    _mine.insert(0, post);
    _details[post.id] = post;
    notifyListeners();
    return post;
  }

  @override
  Future<CampusPost> updatePost(String id, Map<String, dynamic> fields) async {
    _requireUser();
    final post = CampusPost.fromJson(
      _map(
        await _api.request('PATCH', '/posts/$id', body: _postFields(fields)),
      ),
    );
    _replace(post);
    if (post.status != 'published') _posts.removeWhere((p) => p.id == id);
    notifyListeners();
    return post;
  }

  @override
  Future<void> submitPost(String id) async {
    _requireUser();
    await _api.request('POST', '/posts/$id/submit');
    await loadMyPosts();
  }

  @override
  Future<void> loadMyPosts() async {
    _requireUser();
    _mine = _postList(
      await _api.request('GET', '/me/posts', query: {'page_size': 100}),
    );
    notifyListeners();
  }

  @override
  Future<void> loadModeration() async {
    _requireUser();
    _moderation = _postList(
      await _api.request(
        'GET',
        '/moderation/posts',
        query: {'status': 'pending', 'page_size': 100},
      ),
    );
    for (final post in _moderation) {
      _details[post.id] = post;
    }
    notifyListeners();
  }

  @override
  Future<void> moderate(
    String postId,
    String decision, {
    String reason = '',
  }) async {
    _requireUser();
    final decisions = {
      'approve': 'publish',
      'return': 'changes_requested',
      'reject': 'reject',
    };
    final reviewed = _details[postId];
    if (reviewed == null || reviewed.revision.isEmpty) {
      throw const ApiException('Обновите публикацию перед проверкой.');
    }
    await _api.request(
      'POST',
      '/moderation/posts/$postId/decision',
      body: {
        'decision': decisions[decision] ?? decision,
        'expected_updated_at': reviewed.revision,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    _moderation.removeWhere((p) => p.id == postId);
    notifyListeners();
  }

  @override
  Future<List<ModerationEntry>> loadModerationHistory(String postId) async =>
      _items(
        await _api.request('GET', '/moderation/posts/$postId/history'),
      ).map((e) => ModerationEntry.fromJson(_map(e))).toList();
  @override
  Future<String?> pickAndUploadImage() async {
    _requireUser();
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw const ApiException('Выберите фотографию размером до 8 МБ.');
    }
    return _api.upload(bytes, image.name);
  }

  @override
  Future<List<String>> pickAndUploadImages({int remaining = 6}) async {
    _requireUser();
    if (remaining <= 0) return [];
    final images = await ImagePicker().pickMultiImage(
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    final urls = <String>[];
    for (final image in images.take(remaining)) {
      final bytes = await image.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw const ApiException(
          'Выберите фотографии размером до 8 МБ каждая.',
        );
      }
      urls.add(await _api.upload(bytes, image.name));
    }
    return urls;
  }

  @override
  Future<void> appealPost(String postId) async {
    _replace(
      CampusPost.fromJson(
        _map(await _api.request('POST', '/posts/$postId/appeal')),
      ),
    );
    await loadMyPosts();
  }

  @override
  Future<void> toggleTopic(String categoryId) async {
    _requireUser();
    final followed = _user!.interests.contains(categoryId);
    _user = UserProfile.fromJson(
      _map(
        await _api.request(
          followed ? 'DELETE' : 'PUT',
          '/categories/$categoryId/follow',
        ),
      ),
    );
    notifyListeners();
    await loadFeed(mode: _mode, categoryId: _category);
  }

  @override
  void setAppearance({ThemeMode? mode, Color? accent}) {
    if (mode != null) {
      _theme = mode;
      _preferences?.setString('theme', mode.name);
    }
    if (accent != null) {
      _accent = accent;
      _preferences?.setInt('accent', accent.toARGB32());
    }
    notifyListeners();
  }

  @override
  Future<void> setConnection(String url) async {
    if (_api.hasManagedEndpoint) {
      await _api.prepareConnection(force: true);
      await _preferences?.setString(
        'managed_endpoint_${_api.sessionNamespace}',
        _api.baseUrl,
      );
      await loadFeed();
      return;
    }
    if (_api.isOffline) {
      throw const ApiException(
        'Демо-версия работает на этом устройстве без сервера.',
      );
    }
    var normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    final parsed = Uri.tryParse(normalized);
    if (parsed == null ||
        !['http', 'https'].contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const ApiException(
        'Укажите адрес сервера, например http://192.168.1.10:8000',
      );
    }
    if (const bool.fromEnvironment('PUBLIC_BUILD') &&
        parsed.scheme != 'https') {
      throw const ApiException('Для общего сервера нужен адрес с https://');
    }
    final previous = _api.baseUrl;
    final previousToken = _api.token;
    _api.baseUrl = normalized;
    _api.token = null;
    try {
      await _api.request('GET', '/health');
    } catch (_) {
      _api.baseUrl = previous;
      _api.token = previousToken;
      rethrow;
    }
    _user = null;
    _posts = [];
    _saved = [];
    _mine = [];
    _moderation = [];
    _details.clear();
    _chatImages.clear();
    _commentReports.clear();
    _mode = 'all';
    _query = '';
    _category = null;
    await _preferences?.setString('api_base_url', normalized);
    await initialize();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
