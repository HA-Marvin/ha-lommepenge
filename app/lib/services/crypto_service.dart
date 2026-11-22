import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Simple hjælpefunktioner til hashing af PIN-koder og HMAC-signering af
/// sync-requests. Ikke tiltænkt bank-niveau sikkerhed - blot "ikke i
/// klartekst" og en fælles-nøgle-signatur der beskytter mod tilfældige
/// enheder på samme wifi, jf. MVP-scope.
class CryptoService {
  CryptoService._();

  static final Random _random = Random.secure();

  /// Genererer en tilfældig hex-streng med [bytesLength] bytes entropi.
  static String randomHex(int bytesLength) {
    final bytes = List<int>.generate(bytesLength, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Genererer en tilfældig salt til PIN-hashing.
  static String generateSalt() => randomHex(16);

  /// Genererer en delt parringsnøgle (bruges som HMAC-nøgle for sync).
  static String generatePairingKey() => randomHex(32);

  /// SHA-256("$salt:$pin") som hex-streng.
  static String hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$pin'));
    return digest.toString();
  }

  static bool verifyPin(String pin, String salt, String expectedHash) {
    return hashPin(pin, salt) == expectedHash;
  }

  /// HMAC-SHA256([key], [message]) som hex-streng. Bruges til at
  /// signere/validere krop af sync-HTTP-requests.
  static String hmacSha256Hex(String key, List<int> messageBytes) {
    final hmac = Hmac(sha256, utf8.encode(key));
    return hmac.convert(messageBytes).toString();
  }

  /// De sidste 6 tegn af parringsnøglen, uppercased - en kort
  /// backup-kode der kan læses/tastes manuelt hvis QR/kamera driller.
  static String backupCode(String pairingKey) {
    if (pairingKey.length <= 6) return pairingKey.toUpperCase();
    return pairingKey.substring(pairingKey.length - 6).toUpperCase();
  }
}
