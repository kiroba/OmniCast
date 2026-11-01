// Hub connection + contacts for OmniCast 1:1 calls, kept in Android Keystore-backed storage.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'omni_signal_client.dart';

const FlutterSecureStorage _store = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Which node signals for this phone. Default: Omni Node on this phone (127.0.0.1) with the token
/// from Omni Node > Connect apps.
class CastHub {
  final String host;
  final String token;
  const CastHub({this.host = '127.0.0.1', this.token = ''});

  bool get isLocal => host.isEmpty || host == '127.0.0.1' || host == 'localhost';
  String get label => isLocal ? 'Omni Node on this phone' : 'Hub $host';
  SignalHub get signalHub => SignalHub(host: host.isEmpty ? '127.0.0.1' : host, token: token);

  static Future<CastHub> load() async {
    try {
      return CastHub(
        host: await _store.read(key: 'omnicast_hub_host_v1') ?? '127.0.0.1',
        token: await _store.read(key: 'omnicast_hub_token_v1') ?? '',
      );
    } catch (_) {
      return const CastHub();
    }
  }

  Future<void> save() async {
    await _store.write(key: 'omnicast_hub_host_v1', value: host.trim());
    await _store.write(key: 'omnicast_hub_token_v1', value: token.trim());
  }
}

class Contact {
  final String name;
  final String key; // 64-hex Ed25519 public key (their OmniCast "call ID")
  const Contact(this.name, this.key);

  Map<String, String> toJson() => {'name': name, 'key': key};
  String get tag => '${key.substring(0, 4)}…${key.substring(key.length - 4)}';

  static final RegExp keyRe = RegExp(r'^[0-9a-f]{64}$');

  /// Accepts a pasted ID with spaces / uppercase / an "omnicast:" prefix. Null if it isn't a key.
  static String? normalizeKey(String raw) {
    final k = raw.trim().toLowerCase().replaceFirst('omnicast:', '').replaceAll(RegExp(r'\s'), '');
    return keyRe.hasMatch(k) ? k : null;
  }
}

class Contacts {
  static const _k = 'omnicast_contacts_v1';

  static Future<List<Contact>> load() async {
    try {
      final raw = await _store.read(key: _k);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List)
          if (j is Map && j['key'] is String && Contact.keyRe.hasMatch(j['key'] as String))
            Contact((j['name'] as String?) ?? 'Contact', j['key'] as String)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Contact> list) =>
      _store.write(key: _k, value: jsonEncode([for (final c in list) c.toJson()]));
}
