import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// The directory is untrusted. Both its record and the live server must prove
/// possession of the private key pinned in this APK before credentials are sent.
class SignedEndpointDiscovery {
  SignedEndpointDiscovery({
    required this.directoryUrl,
    required String publicKey,
    required this.instance,
    http.Client? client,
  }) : _key = SimplePublicKey(
         base64Decode(publicKey),
         type: KeyPairType.ed25519,
       ),
       _client = client ?? http.Client();

  final String directoryUrl, instance;
  final SimplePublicKey _key;
  final http.Client _client;
  final _algorithm = Ed25519();

  static SignedEndpointDiscovery? fromEnvironment() {
    const directory = String.fromEnvironment('DISCOVERY_URL');
    if (directory.isEmpty) return null;
    return SignedEndpointDiscovery(
      directoryUrl: directory,
      publicKey: const String.fromEnvironment('SERVER_PUBLIC_KEY'),
      instance: const String.fromEnvironment('SERVER_INSTANCE'),
    );
  }

  String _validOrigin(dynamic value) {
    if (value is! String) throw const FormatException('Missing endpoint');
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty ||
        uri.hasPort) {
      throw const FormatException('Invalid endpoint');
    }
    return value;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    // Deliberately use a new request without bearer tokens and disable redirects.
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 9));
    if (response.statusCode != 200) {
      throw const FormatException('Endpoint unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 9),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) {
        throw const FormatException('Oversized directory response');
      }
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<bool> _verify(List<int> bytes, dynamic signature) async {
    if (signature is! String || signature.length > 100) return false;
    final decoded = base64Decode(signature);
    return decoded.length == 64 &&
        _key.bytes.length == 32 &&
        await _algorithm.verify(
          bytes,
          signature: Signature(decoded, publicKey: _key),
        );
  }

  Future<String> _readDirectory() async {
    final record = await _getJson(Uri.parse(directoryUrl));
    final payloadText = record['payload'];
    if (payloadText is! String || payloadText.length > 6000) {
      throw const FormatException('Invalid record');
    }
    final bytes = base64Decode(payloadText);
    if (!await _verify(bytes, record['signature'])) {
      throw const FormatException('Untrusted record');
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map;
    if (data['service'] != 'pulse' ||
        data['version'] != 1 ||
        data['instance'] != instance ||
        !DateTime.parse(
          data['valid_until'] as String,
        ).isAfter(DateTime.now())) {
      throw const FormatException('Expired or incorrect record');
    }
    return _validOrigin(data['url']);
  }

  Future<void> prove(String origin) async {
    _validOrigin(origin);
    final random = Random.secure();
    final nonce = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final proof = await _getJson(
      Uri.parse(
        '$origin/api/server-proof',
      ).replace(queryParameters: {'nonce': nonce}),
    );
    final bytes = utf8.encode('pulse-server-proof:v1:$instance:$origin:$nonce');
    if (proof['instance'] != instance ||
        proof['nonce'] != nonce ||
        proof['url'] != origin ||
        !await _verify(bytes, proof['signature'])) {
      throw const FormatException('Server identity verification failed');
    }
  }

  Future<String> resolve(
    String current, {
    bool refreshDirectory = false,
  }) async {
    if (!refreshDirectory) {
      try {
        await prove(current);
        return current;
      } catch (_) {
        /* The tunnel may have changed. Consult the signed record. */
      }
    }
    try {
      final endpoint = await _readDirectory();
      await prove(endpoint);
      return endpoint;
    } catch (_) {
      // A directory outage or tampering must never redirect a session. The old
      // endpoint is usable only after a fresh challenge with the pinned key.
      await prove(current);
      return current;
    }
  }

  void close() => _client.close();
}
