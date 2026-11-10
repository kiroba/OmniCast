import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

/// ============================================================================
/// OMNICAST IDENTITY SEED STORE (flutter_secure_storage)
/// ============================================================================
/// Keeps this install's Ed25519 seed in flutter_secure_storage, which on
/// Android encrypts it with an AES key held in the Android Keystore
/// (EncryptedSharedPreferences). Same construction as KickBack's and
/// Plaza-Brawler's stores - OmniCast was the last app still on the plain
/// SQLite default.
///
/// Honest limits (same as the other apps' stores):
/// - The Keystore key is not set to "require user authentication", so the
///   seed can be decrypted without a fingerprint; signing happens in Dart
///   memory because Android Keystore has no Ed25519 signing on most devices.
///
/// Migration: earlier builds kept the seed in the shared omni_core SQLite
/// (`ed25519_seed` via SqliteSeedStore). On first read we copy it here, read
/// it back to confirm, then delete the SQLite copy, so the call identity
/// (public key / call ID) does not change.
/// ============================================================================
class OmniCastSeedStore implements IdentitySeedStore {
  static const String _key = 'omnicast_ed25519_seed_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<List<int>?> read() async {
    final v = await _storage.read(key: _key);
    if (v != null) return base64Decode(v);

    // One-time move from the old SQLite location.
    final legacy = SqliteSeedStore();
    final old = await legacy.read();
    if (old == null) return null;
    await write(old);
    final check = await _storage.read(key: _key);
    if (check != null && check == base64Encode(old)) {
      await legacy.delete();
    }
    return old;
  }

  @override
  Future<void> write(List<int> seed) =>
      _storage.write(key: _key, value: base64Encode(seed));
}
