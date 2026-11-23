import 'dart:async';

import 'package:flutter/services.dart';

/// The app's bridge to Android (see `MainActivity.kt`): links from Home
/// Assistant's install page, the app's version, installation of updates and
/// the child's tablet's background service (`LockService.kt`). On other
/// platforms (and in tests) it answers neutrally.
class NativeBridge {
  static const _channel = MethodChannel('lommepenge/native');

  final _links = StreamController<String>.broadcast();
  final _installFailures = StreamController<String?>.broadcast();
  final _refreshRequests = StreamController<void>.broadcast();

  NativeBridge() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'link':
          _links.add(call.arguments as String);
        case 'installFailed':
          _installFailures.add(call.arguments as String?);
        case 'refresh':
          _refreshRequests.add(null);
      }
    });
  }

  /// Links that open the app while it is running.
  Stream<String> get links => _links.stream;

  /// Errors from Android's installation of an update (`null` when Android
  /// gives no message).
  Stream<String?> get installFailures => _installFailures.stream;

  /// The background service has changed something in HA (reported use of
  /// the tablet): fetch the state now.
  Stream<void> get refreshRequests => _refreshRequests.stream;

  /// The link that started the app, if any (only once).
  Future<String?> takeInitialLink() => _call<String>('takeLink');

  Future<({String name, int code})> appVersion() async {
    final info = await _call<Map>('appVersion');
    return (
      name: (info?['name'] as String?) ?? '',
      code: (info?['code'] as num?)?.toInt() ?? 0,
    );
  }

  /// Home Assistant instances on the home network (mDNS), e.g. to fill in the
  /// address on the connect screen. Empty list if none are found.
  Future<List<({String name, String url})>> discoverHa() async {
    final found = await _call<List>('discoverHa') ?? const [];
    return [
      for (final item in found.whereType<Map>())
        if (item['url'] is String)
          (
            name: (item['name'] as String?) ?? 'Home Assistant',
            url: item['url'] as String,
          ),
    ];
  }

  /// Whether Android allows the app to install updates.
  Future<bool> canInstall() async => await _call<bool>('canInstall') ?? false;

  Future<void> openInstallSettings() => _call<void>('openInstallSettings');

  Future<void> installApk(String path) =>
      _call<void>('installApk', {'path': path});

  /// Shows a notification about a new version. [channelName] is the name of
  /// Android's notification channel (shown in the app's system settings).
  Future<void> notify(String title, String text, {required String channelName}) =>
      _call<void>(
        'notify',
        {'title': title, 'text': text, 'channelName': channelName},
      );

  /// Starts ([enabled]) or stops the child's tablet's foreground service.
  /// [texts] are its texts in the app's language: `statusChannel`,
  /// `messagesChannel`, `active` and `lockedUntil` (with `{time}`).
  Future<void> configureChildService({
    required bool enabled,
    Map<String, String> texts = const {},
  }) =>
      _call<void>('childService', {'enabled': enabled, 'texts': texts});

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null; // e.g. Windows build or tests
    }
  }
}
