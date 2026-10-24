import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/services/api_client.dart';
import 'package:pulse/services/endpoint_discovery.dart';

const instance = 'test-server-identity';
const directory = 'https://directory.example/record';
const oldOrigin = 'https://old.lhr.life';
const newOrigin = 'https://new.lhr.life';
final algorithm = Ed25519();
late SimpleKeyPair pair;
late String publicKey;

http.Response jsonReply(Object value, [int code = 200]) =>
    http.Response(jsonEncode(value), code);
Future<String> sign(List<int> bytes) async =>
    base64Encode((await algorithm.sign(bytes, keyPair: pair)).bytes);
Future<Map<String, dynamic>> record(
  String origin, {
  bool expired = false,
}) async {
  final bytes = utf8.encode(
    jsonEncode({
      'service': 'pulse',
      'version': 1,
      'instance': instance,
      'url': origin,
      'valid_until': DateTime.now()
          .add(Duration(days: expired ? -1 : 1))
          .toUtc()
          .toIso8601String(),
    }),
  );
  return {'payload': base64Encode(bytes), 'signature': await sign(bytes)};
}

Future<http.Response> proof(
  http.Request request, {
  String? actualOrigin,
  bool invalid = false,
}) async {
  final nonce = request.url.queryParameters['nonce'];
  final origin = actualOrigin ?? request.url.origin;
  return jsonReply({
    'instance': instance,
    'url': origin,
    'nonce': nonce,
    'signature': invalid
        ? base64Encode(List.filled(64, 0))
        : await sign(
            utf8.encode('pulse-server-proof:v1:$instance:$origin:$nonce'),
          ),
  });
}

SignedEndpointDiscovery discovery(http.Client client) =>
    SignedEndpointDiscovery(
      directoryUrl: directory,
      publicKey: publicKey,
      instance: instance,
      client: client,
    );

void main() {
  setUp(() async {
    pair = await algorithm.newKeyPairFromSeed(List.generate(32, (i) => i + 1));
    publicKey = base64Encode((await pair.extractPublicKey()).bytes);
  });

  test(
    'Signed discovery and challenge receive no credentials; the verified API does',
    () async {
      final signed = await record(newOrigin);
      final transport = MockClient((request) async {
        if (request.url.toString() == directory ||
            request.url.path == '/api/server-proof') {
          expect(request.headers['Authorization'], isNull);
          expect(request.followRedirects, false);
          return request.url.toString() == directory
              ? jsonReply(signed)
              : proof(request);
        }
        expect(request.url.origin, newOrigin);
        expect(request.headers['Authorization'], 'Bearer private-session');
        return jsonReply({'status': 'ok'});
      });
      final api = ApiClient(
        baseUrl: oldOrigin,
        client: transport,
        discovery: discovery(transport),
      )..token = 'private-session';
      await api.prepareConnection(force: true);
      await api.request('GET', '/me');
      expect(api.baseUrl, newOrigin);
      expect(api.sessionNamespace, instance);
      api.close();
    },
  );

  for (final variant in [
    'tampered',
    'expired',
    'http',
    'imposter',
    'reassigned',
  ]) {
    test('Rejects $variant endpoint before any credentials are sent', () async {
      final signed = await record(
        variant == 'http' ? 'http://evil.example' : newOrigin,
        expired: variant == 'expired',
      );
      if (variant == 'tampered') {
        signed['payload'] = base64Encode(utf8.encode('{}'));
      }
      final transport = MockClient((request) async {
        expect(request.headers['Authorization'], isNull);
        if (request.url.toString() == directory) return jsonReply(signed);
        if (request.url.origin == oldOrigin) return jsonReply({}, 502);
        expect(variant, anyOf('imposter', 'reassigned'));
        return proof(
          request,
          invalid: variant == 'imposter',
          actualOrigin: variant == 'reassigned' ? oldOrigin : null,
        );
      });
      final api = ApiClient(
        baseUrl: oldOrigin,
        client: transport,
        discovery: discovery(transport),
      )..token = 'private-session';
      await expectLater(
        api.prepareConnection(force: true),
        throwsA(isA<ApiException>()),
      );
      expect(api.baseUrl, oldOrigin);
      expect(api.token, 'private-session');
      api.close();
    });
  }

  test(
    'A tunnel rotation retries reading with the same session, never retries a write',
    () async {
      final signed = await record(newOrigin);
      var reads = 0, writes = 0;
      final transport = MockClient((request) async {
        if (request.url.path == '/api/server-proof') return proof(request);
        if (request.url.toString() == directory) return jsonReply(signed);
        expect(request.headers['Authorization'], 'Bearer private-session');
        if (request.method == 'POST') {
          writes++;
          return jsonReply({}, 503);
        }
        reads++;
        return jsonReply({
          'status': 'ok',
        }, request.url.origin == oldOrigin ? 502 : 200);
      });
      final api = ApiClient(
        baseUrl: oldOrigin,
        client: transport,
        discovery: discovery(transport),
      )..token = 'private-session';
      expect(await api.request('GET', '/posts'), {'status': 'ok'});
      expect(reads, 2);
      expect(api.baseUrl, newOrigin);
      expect(api.sessionNamespace, instance);
      await expectLater(
        api.request('POST', '/comments', body: {'body': 'test'}),
        throwsA(isA<ApiException>()),
      );
      expect(writes, 1);
      expect(api.token, 'private-session');
      api.close();
    },
  );

  test(
    'A directory outage allows the cached endpoint only after a fresh proof',
    () async {
      var proofs = 0;
      final transport = MockClient((request) async {
        expect(request.headers['Authorization'], isNull);
        if (request.url.toString() == directory) return jsonReply({}, 503);
        proofs++;
        return proof(request);
      });
      expect(
        await discovery(transport).resolve(oldOrigin, refreshDirectory: true),
        oldOrigin,
      );
      expect(proofs, 1);
      transport.close();
    },
  );
}
