import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'endpoint_discovery.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    SignedEndpointDiscovery? discovery,
  }) : _client = client ?? http.Client(),
       _discovery = discovery;

  factory ApiClient.production({required String baseUrl}) => ApiClient(
    baseUrl: baseUrl,
    discovery: SignedEndpointDiscovery.fromEnvironment(),
  );

  String baseUrl;
  String? token;
  bool get isOffline => false;
  final http.Client _client;
  final SignedEndpointDiscovery? _discovery;
  Future<void>? _resolving;
  DateTime? _verifiedAt;
  bool get hasManagedEndpoint => _discovery != null;
  String get sessionNamespace => _discovery?.instance ?? baseUrl;

  Future<void> prepareConnection({bool force = false}) async {
    if (_discovery == null) return;
    if (_resolving != null) return _resolving!;
    if (!force &&
        _verifiedAt != null &&
        DateTime.now().difference(_verifiedAt!) < const Duration(seconds: 30)) {
      return;
    }
    Future<void> resolve() async {
      try {
        baseUrl = await _discovery.resolve(baseUrl, refreshDirectory: force);
        _verifiedAt = DateTime.now();
      } catch (_) {
        _verifiedAt = null;
        throw const ApiException(
          'Не удалось подтвердить соединение с сервером. Повторите попытку через несколько секунд.',
        );
      }
    }

    _resolving = resolve();
    try {
      await _resolving;
    } finally {
      _resolving = null;
    }
  }

  Uri uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$baseUrl/api$path').replace(
        queryParameters: query == null
            ? null
            : {
                for (final item in query.entries)
                  if (item.value != null && item.value.toString().isNotEmpty)
                    item.key: item.value.toString(),
              },
      );

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    await prepareConnection();
    try {
      return await _requestOnce(method, path, body: body, query: query);
    } on ApiException catch (error) {
      if (hasManagedEndpoint &&
          method == 'GET' &&
          (error.statusCode == null ||
              [502, 503, 504].contains(error.statusCode))) {
        await prepareConnection(force: true);
        return _requestOnce(method, path, body: body, query: query);
      }
      rethrow;
    }
  }

  Future<dynamic> _requestOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final request = http.Request(method, uri(path, query));
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 20));
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'Сервер не ответил. Проверьте соединение и повторите попытку.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Нет соединения с сервером. Проверьте интернет и адрес сервера в настройках.',
      );
    } on FormatException {
      throw const ApiException('Сервер прислал некорректный ответ.');
    }
  }

  Future<String> upload(
    List<int> bytes,
    String filename, {
    String path = '/uploads',
  }) async {
    await prepareConnection();
    final request = http.MultipartRequest('POST', uri(path));
    request.followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 40)),
      ).timeout(const Duration(seconds: 40));
      final data = _decode(response);
      if (data is Map && data['url'] is String) return data['url'] as String;
      throw const ApiException('Не удалось получить адрес фотографии.');
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'Загрузка заняла слишком много времени. Попробуйте ещё раз.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Не удалось загрузить фотографию. Проверьте соединение.',
      );
    }
  }

  Future<Uint8List> downloadPrivateImage(String path) async {
    if (!RegExp(r'^/api/chats/\d+/images/[a-f0-9]{40}\.jpg$').hasMatch(path)) {
      throw const ApiException('Некорректный адрес фотографии.');
    }
    await prepareConnection();
    try {
      final request = http.Request('GET', Uri.parse('$baseUrl$path'))
        ..followRedirects = false;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode >= 400) _decode(response);
      return response.bodyBytes;
    } on TimeoutException {
      throw const ApiException('Не удалось загрузить фотографию.');
    } on http.ClientException {
      throw const ApiException('Нет соединения с сервером.');
    }
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw ApiException(
        'Соединение с сервером изменилось. Обновите экран.',
        statusCode: 503,
      );
    }
    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode < 400) rethrow;
      }
    }
    if (response.statusCode >= 400) {
      var message = 'Не удалось выполнить запрос. Попробуйте ещё раз.';
      final detail = data is Map ? data['detail'] : null;
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final field = (detail.first is Map ? detail.first['loc'] : null);
        final fieldName = field is List && field.isNotEmpty
            ? field.last.toString()
            : '';
        const fields = {
          'email': 'электронную почту',
          'password': 'пароль',
          'name': 'имя',
          'title': 'заголовок',
          'body': 'текст',
          'event_start': 'дату мероприятия',
          'registration_url': 'ссылку регистрации',
        };
        message = fields.containsKey(fieldName)
            ? 'Проверьте ${fields[fieldName]}.'
            : 'Проверьте заполненные поля.';
      } else if (response.statusCode == 401) {
        message = 'Войдите в аккаунт, чтобы продолжить.';
      } else if (response.statusCode == 403) {
        message = 'Для этого действия недостаточно прав.';
      } else if (response.statusCode == 404) {
        message = 'Материал не найден или больше недоступен.';
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    return data;
  }

  void close() {
    _client.close();
    _discovery?.close();
  }
}
