import 'dart:async';

import 'package:flutter/services.dart';

/// Appens bro til Android (se `MainActivity.kt`): links fra Home
/// Assistants installationsside, appens version og installation af
/// opdateringer. På andre platforme (og i tests) svarer den neutralt.
class NativeBridge {
  static const _channel = MethodChannel('lommepenge/native');

  final _links = StreamController<String>.broadcast();
  final _installFailures = StreamController<String>.broadcast();

  NativeBridge() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'link':
          _links.add(call.arguments as String);
        case 'installFailed':
          _installFailures.add(
            (call.arguments as String?) ?? 'Installationen mislykkedes.',
          );
      }
    });
  }

  /// Links der åbner appen, mens den kører.
  Stream<String> get links => _links.stream;

  /// Fejl fra Androids installation af en opdatering.
  Stream<String> get installFailures => _installFailures.stream;

  /// Linket der startede appen, hvis nogen (kun én gang).
  Future<String?> takeInitialLink() => _call<String>('takeLink');

  Future<({String name, int code})> appVersion() async {
    final info = await _call<Map>('appVersion');
    return (
      name: (info?['name'] as String?) ?? '',
      code: (info?['code'] as num?)?.toInt() ?? 0,
    );
  }

  /// Om Android tillader appen at installere opdateringer.
  Future<bool> canInstall() async => await _call<bool>('canInstall') ?? false;

  Future<void> openInstallSettings() => _call<void>('openInstallSettings');

  Future<void> installApk(String path) =>
      _call<void>('installApk', {'path': path});

  Future<void> notify(String title, String text) =>
      _call<void>('notify', {'title': title, 'text': text});

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null; // fx Windows-build eller tests
    }
  }
}
