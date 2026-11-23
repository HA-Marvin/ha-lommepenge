import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../l10n/l10n.dart';
import 'crypto_service.dart';

/// The connection to Home Assistant, stored after pairing. [key] is the
/// device's own key from HA - the app never knows HA's own users/tokens.
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

/// A pairing link from "Add device" in HA: where HA is, and the one-time code.
class ConnectLink {
  final Uri baseUrl;
  final String token;
  const ConnectLink(this.baseUrl, this.token);
}

/// Reads a link from the QR code or the install page:
///
/// - `http://192.168.1.10:8123/api/lommepenge/install/<token>` (the QR code)
/// - `lommepenge://pair?url=http://192.168.1.10:8123&token=<token>`
///   ("Open the app and connect" on the install page)
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

/// Pairing with a code typed by hand (device without a camera): HA's address,
/// e.g. `192.168.1.10` or `http://homeassistant.local:8123`, and the code from
/// "Add device". If the scheme or port is missing, `http` and 8123 are used.
ConnectLink? connectLinkFromCode(String address, String code) {
  var text = address.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  final normalizedCode = code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (uri == null || uri.host.isEmpty || normalizedCode.isEmpty) return null;
  final base = Uri(
    scheme: uri.scheme,
    host: uri.host,
    // Uri hides default ports (e.g. :443), so look for a port in the text.
    port: RegExp(r'://[^/]+:\d+').hasMatch(text) ? uri.port : 8123,
  );
  return ConnectLink(base, normalizedCode);
}

/// Response from pairing.
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

/// Response from a signed request.
class HaResult {
  final Map<String, dynamic>? state;
  final String? errorMessage;

  /// HA no longer knows the device (removed under "Devices" in HA), or the
  /// device's key is no longer valid. The ONLY case where the app forgets the
  /// connection - a wrong clock is corrected instead (see
  /// [HaClient.clockOffset]).
  final bool unauthorized;

  /// HA could not be reached - the action can be sent again later.
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

/// The app's client for the Lommepenge integration in Home Assistant.
///
/// All requests after pairing are signed with the device's key over
/// timestamp, method, path and body (HMAC-SHA256), so HA knows which device -
/// and thereby which role - is asking. Every request carries the language
/// chosen in the app (`X-Lommepenge-Language`), so HA's error messages come
/// back in it - never the phone's language.
class HaClient {
  static const apiPrefix = '/api/lommepenge';
  static const languageHeader = 'X-Lommepenge-Language';

  final Duration timeout;

  /// The app's version (sent along, so HA can show it per device).
  String appVersion = '';
  int appVersionCode = 0;

  /// The texts for the app's own error messages; set by `AppState` when the
  /// language changes.
  AppLocalizations l10n = l10nFor(defaultLanguage);

  /// How far HA's clock is ahead of this device's (HA time - device time).
  /// Added to the device's clock when signing, so a device with a wrong
  /// clock keeps working without a new pairing. Learned from HA's
  /// `clock_skew` answer (which carries HA's own time); time zones do not
  /// matter, as requests are signed with Unix time.
  Duration clockOffset = Duration.zero;

  /// Called when [clockOffset] has been corrected, so it can be stored.
  void Function(Duration offset)? onClockOffsetChanged;

  /// Error codes from HA (`code` in a 401 answer) that mean the device's key
  /// is revoked or invalid. Every other 401 (e.g. `clock_skew`) keeps the
  /// connection.
  static const revokedCodes = {'device_not_connected', 'invalid_signature'};

  HaClient({this.timeout = const Duration(seconds: 8)});

  Future<PairResult> pair(ConnectLink link) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(link.baseUrl.replace(path: '$apiPrefix/pair'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(languageHeader, l10n.localeName);
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
              l10n.haRejectedConnection('${response.statusCode}'),
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
      return PairResult.failure(l10n.cannotReachHaHomeNetwork);
    } on TimeoutException {
      return PairResult.failure(l10n.haTimeout);
    } catch (e) {
      return PairResult.failure(l10n.unexpectedError('$e'));
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

  /// Signature headers for a request - the same calculation as HA's `sign()`.
  Map<String, String> signedHeaders(
    HaConnection connection,
    String method,
    String path,
    List<int> body, {
    DateTime? now,
  }) {
    final timestamp =
        ((now ?? DateTime.now().add(clockOffset)).millisecondsSinceEpoch ~/
                1000)
            .toString();
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
      languageHeader: l10n.localeName,
    };
  }

  /// Downloads the latest APK from HA to [target]. Returns an error message,
  /// or `null` when the file has been downloaded.
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
        return l10n.haUpdateFailed('${response.statusCode}');
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
      return l10n.cannotReachHa;
    } on TimeoutException {
      return l10n.haTimeout;
    } catch (e) {
      return l10n.updateDownloadFailed('$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<HaResult> _send(
    HaConnection connection,
    String method,
    String path,
    List<int> body, {
    bool retryOnClockSkew = true,
  }) async {
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
        final code = decoded['code'];
        final serverTime = decoded['serverTime'];
        if (code == 'clock_skew' && serverTime is num) {
          // The device's clock is wrong: correct for the difference and try
          // once more. Never a reason to forget the connection.
          clockOffset = Duration(
            milliseconds: (serverTime * 1000).round() -
                DateTime.now().millisecondsSinceEpoch,
          );
          onClockOffsetChanged?.call(clockOffset);
          if (retryOnClockSkew) {
            client.close(force: true);
            return await _send(
              connection,
              method,
              path,
              body,
              retryOnClockSkew: false,
            );
          }
        }
        return HaResult.failure(
          decoded['error'] as String? ?? l10n.deviceNoLongerConnected,
          // An older HA without `code`: as before, a 401 means the device
          // is no longer connected.
          unauthorized: code == null || revokedCodes.contains(code),
        );
      }
      if (response.statusCode != 200) {
        return HaResult.failure(
          decoded['error'] as String? ?? l10n.haError('${response.statusCode}'),
        );
      }
      return HaResult.ok(decoded);
    } on SocketException {
      return HaResult.failure(l10n.noConnectionCheckNetwork, offline: true);
    } on TimeoutException {
      return HaResult.failure(l10n.haTimeoutRetry, offline: true);
    } catch (e) {
      return HaResult.failure(l10n.unexpectedError('$e'));
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
