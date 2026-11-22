import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Simple helpers for hashing PIN codes and HMAC signing of requests. Not
/// meant as bank-level security - just "not in plain text" and a shared-key
/// signature that protects against random devices on the same Wi-Fi.
class CryptoService {
  CryptoService._();

  static final Random _random = Random.secure();

  /// Generates a random hex string with [bytesLength] bytes of entropy.
  static String randomHex(int bytesLength) {
    final bytes = List<int>.generate(bytesLength, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generates a random salt for PIN hashing.
  static String generateSalt() => randomHex(16);

  /// Generates a shared pairing key (used as HMAC key).
  static String generatePairingKey() => randomHex(32);

  /// SHA-256("$salt:$pin") as a hex string.
  static String hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$pin'));
    return digest.toString();
  }

  static bool verifyPin(String pin, String salt, String expectedHash) {
    return hashPin(pin, salt) == expectedHash;
  }

  /// HMAC-SHA256([key], [message]) as a hex string. Used to sign/validate
  /// the requests to Home Assistant.
  static String hmacSha256Hex(String key, List<int> messageBytes) {
    final hmac = Hmac(sha256, utf8.encode(key));
    return hmac.convert(messageBytes).toString();
  }

  /// The last 6 characters of the pairing key, upper case - a short backup
  /// code that can be read/typed by hand if QR/camera acts up.
  static String backupCode(String pairingKey) {
    if (pairingKey.length <= 6) return pairingKey.toUpperCase();
    return pairingKey.substring(pairingKey.length - 6).toUpperCase();
  }
}
