import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_service.dart';

/// Forbindelsen til Home Assistant, gemt efter parring. [key] er enhedens
/// egen nøgle fra HA - appen kender aldrig HA's egne brugere/tokens.
class HaConnection {
  final Uri baseUrl;
  final String deviceId;
  final String key;

  const HaConnection({
    required this.baseUrl,
    required this.deviceId,
    required this.key,
  });
}

/// Et parringslink fra "Tilføj enhed" i HA: hvor HA er, og engangskoden.
class ConnectLink {
  final Uri baseUrl;
  final String token;
  const ConnectLink(this.baseUrl, this.token);
}

/// Læser et link fra QR-koden eller installationssiden:
///
/// - `http://192.168.1.10:8123/api/lommepenge/install/<token>` (QR-koden)
/// - `lommepenge://pair?url=http://192.168.1.10:8123&token=<token>`
///   ("Åbn appen og forbind" på installationssiden)
ConnectLink? parseConnectLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return null;
  if (uri.scheme == 'lommepenge') {
    final base = Uri.tryParse(uri.queryParameters['url'] ?? '');
    final token = uri.queryParameters['token'];
    if (base == null || !base.hasScheme || token == null || token.isEmpty) {
      return null;
    }
    return ConnectLink(base, token);
  }
  final segments = uri.pathSegments;
  final i = segments.indexOf('install');
  if ((uri.scheme == 'http' || uri.scheme == 'https') &&
      i > 0 &&
      segments[i - 1] == 'lommepenge' &&
      i + 1 < segments.length) {
    final base = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    return ConnectLink(base, segments[i + 1]);
  }
  return null;
}

/// Svar fra parringen.
class PairResult {
  final String? deviceId;
  final String? deviceKey;
  final String? role;
  final String? childId;
  final String? deviceName;
  final String? familyName;
  final String? errorMessage;

  const PairResult.ok({
    required this.deviceId,
    required this.deviceKey,
    required this.role,
    required this.childId,
    required this.deviceName,
    required this.familyName,
  }) : errorMessage = null;

  const PairResult.failure(this.errorMessage)
      : deviceId = null,
        deviceKey = null,
        role = null,
        childId = null,
        deviceName = null,
        familyName = null;

  bool get success => errorMessage == null;
}

/// Svar fra et signeret kald.
class HaResult {
  final Map<String, dynamic>? state;
  final String? errorMessage;

  /// HA kender ikke længere enheden (fjernet under "Enheder" i HA).
  final bool unauthorized;

  /// HA kunne ikke nås - handlingen kan sendes igen senere.
  final bool offline;

  const HaResult.ok(this.state)
      : errorMessage = null,
        unauthorized = false,
        offline = false;

  const HaResult.failure(
    this.errorMessage, {
    this.unauthorized = false,
    this.offline = false,
  }) : state = null;

  bool get success => errorMessage == null;
}

/// Appens klient til Lommepenge-integrationen i Home Assistant.
///
/// Alle kald efter parringen signeres med enhedens nøgle over tidspunkt,
/// metode, sti og krop (HMAC-SHA256), så HA ved hvilken enhed - og dermed
/// hvilken rolle - der spørger.
class HaClient {
  static const apiPrefix = '/api/lommepenge';

  final Duration timeout;

  /// Appens version (sendes med, så HA kan vise den pr. enhed).
  String appVersion = '';
  int appVersionCode = 0;

  HaClient({this.timeout = const Duration(seconds: 8)});

  Future<PairResult> pair(ConnectLink link) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(link.baseUrl.replace(path: '$apiPrefix/pair'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'token': link.token,
        'appVersion': appVersion,
        'appVersionCode': appVersionCode,
      })));
      final response = await request.close().timeout(timeout);
      final body = await _decode(response);
      if (response.statusCode != 200) {
        return PairResult.failure(
          body['error'] as String? ??
              'Home Assistant afviste forbindelsen (${response.statusCode}).',
        );
      }
      return PairResult.ok(
        deviceId: body['deviceId'] as String?,
        deviceKey: body['deviceKey'] as String?,
        role: body['role'] as String?,
        childId: body['childId'] as String?,
        deviceName: body['deviceName'] as String?,
        familyName: body['familyName'] as String?,
      );
    } on SocketException {
      return const PairResult.failure(
        'Kan ikke nå Home Assistant. Er enheden på hjemmenettet?',
      );
    } on TimeoutException {
      return const PairResult.failure('Home Assistant svarede ikke i tide.');
    } catch (e) {
      return PairResult.failure('Uventet fejl: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<HaResult> fetchState(HaConnection connection) =>
      _send(connection, 'GET', '$apiPrefix/state', const []);

  Future<HaResult> sendAction(
    HaConnection connection,
    Map<String, dynamic> action,
  ) =>
      _send(
        connection,
        'POST',
        '$apiPrefix/action',
        utf8.encode(jsonEncode(action)),
      );

  /// Signatur-headere for et kald - samme beregning som HA's `sign()`.
  Map<String, String> signedHeaders(
    HaConnection connection,
    String method,
    String path,
    List<int> body, {
    DateTime? now,
  }) {
    final timestamp =
        ((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000).toString();
    final message = [
      ...utf8.encode('$timestamp\n${method.toUpperCase()}\n$path\n'),
      ...body,
    ];
    return {
      'X-Device-Id': connection.deviceId,
      'X-Timestamp': timestamp,
      'X-Signature': CryptoService.hmacSha256Hex(connection.key, message),
      'X-App-Version': appVersion,
      'X-App-Version-Code': '$appVersionCode',
    };
  }

  /// Henter den nyeste APK fra HA til [target]. Returnerer en fejlbesked,
  /// eller `null` når filen er hentet.
  Future<String?> downloadApk(
    HaConnection connection,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    const path = '$apiPrefix/apk';
    try {
      final request = await client
          .getUrl(connection.baseUrl.replace(path: path))
          .timeout(timeout);
      signedHeaders(connection, 'GET', path, const [])
          .forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 'Home Assistant kunne ikke levere opdateringen '
            '(${response.statusCode}).';
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      final sink = target.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      return null;
    } on SocketException {
      return 'Kan ikke nå Home Assistant.';
    } on TimeoutException {
      return 'Home Assistant svarede ikke i tide.';
    } catch (e) {
      return 'Kunne ikke hente opdateringen: $e';
    } finally {
      client.close(force: true);
    }
  }

  Future<HaResult> _send(
    HaConnection connection,
    String method,
    String path,
    List<int> body,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method, connection.baseUrl.replace(path: path))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      signedHeaders(connection, method, path, body)
          .forEach(request.headers.set);
      if (body.isNotEmpty) request.add(body);
      final response = await request.close().timeout(timeout);
      final decoded = await _decode(response);
      if (response.statusCode == 401) {
        return HaResult.failure(
          decoded['error'] as String? ??
              'Enheden er ikke længere forbundet til Home Assistant.',
          unauthorized: true,
        );
      }
      if (response.statusCode != 200) {
        return HaResult.failure(
          decoded['error'] as String? ??
              'Home Assistant svarede med fejl (${response.statusCode}).',
        );
      }
      return HaResult.ok(decoded);
    } on SocketException {
      return const HaResult.failure(
        'Ingen forbindelse til Home Assistant. Tjek at enheden er på '
        'hjemmenettet.',
        offline: true,
      );
    } on TimeoutException {
      return const HaResult.failure(
        'Home Assistant svarede ikke i tide. Prøver igen senere.',
        offline: true,
      );
    } catch (e) {
      return HaResult.failure('Uventet fejl: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _decode(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
