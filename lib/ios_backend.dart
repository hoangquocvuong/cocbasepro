import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class ApiFailure implements Exception {
  final int status;
  final Object? detail;
  ApiFailure(this.status, this.detail);
  @override
  String toString() => 'Request failed ($status): $detail';
}

class IosBackend {
  static const origin = 'https://ios-api.basecoc.net';
  static const store = MethodChannel('basecoc/storekit');
  final storage = const FlutterSecureStorage();
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  String? session;
  String? accountToken;
  Future<void>? _initializing;
  Future<void> initialize() => _initializing ??= _initialize().whenComplete(() => _initializing = null);
  Future<void> _initialize() async {
    session ??= await storage.read(key: 'ios_session_v8');
    if (session == null) {
      final data = await request('account/create', body: {}, auth: false);
      session = data['session_token'] as String;
      await storage.write(key: 'ios_session_v8', value: session);
    }
    final data = await request('account/refresh', body: {});
    accountToken = data['app_account_token'] as String;
  }
  Future<Map<String, dynamic>> request(String path, {Map<String, dynamic>? body, bool auth = true}) async {
    final req = await _client.openUrl(body == null ? 'GET' : 'POST', Uri.parse('$origin/api/ios/$path'));
    req.followRedirects = false;
    if (auth) {
      if (session == null) throw StateError('Account not initialized');
      req.headers.set('Authorization', 'Bearer $session');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 70));
    final raw = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 70));
    final dynamic decoded = jsonDecode(raw);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiFailure(res.statusCode, decoded is Map ? decoded['detail'] : null);
    }
    return Map<String, dynamic>.from(decoded as Map);
  }
  Future<Map<String, dynamic>> verify(Map tx, {bool restore = false}) async {
    final data = await request(restore ? 'vip/restore' : 'vip/verify', body: {
      'transaction_id': tx['transaction_id'], 'environment': tx['environment'],
    });
    await store.invokeMethod('finish', {'transaction_id': tx['transaction_id']});
    return data;
  }
  Future<String> copy(String id) async {
    final result = await request('base/copy', body: {'base_id': id, 'request_id': const Uuid().v4()});
    return result['link'] as String;
  }
}
