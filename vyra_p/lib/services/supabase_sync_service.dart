import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SupabaseSyncService {
  static const String defaultUrl = "https://vyra-kp.supabase.co";
  static const String defaultAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.placeholder";

  final String supabaseUrl;
  final String anonKey;

  SupabaseSyncService({
    this.supabaseUrl = defaultUrl,
    this.anonKey = defaultAnonKey,
  });

  bool get isConfigured =>
      !supabaseUrl.contains("placeholder") &&
      !anonKey.contains("placeholder") &&
      supabaseUrl.isNotEmpty &&
      anonKey.isNotEmpty;

  Future<List<Map<String, dynamic>>> fetchTable(String table, {String? filterField, String? filterValue}) async {
    if (!isConfigured) return [];

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      var queryUri = "$supabaseUrl/rest/v1/$table?select=*";
      if (filterField != null && filterValue != null) {
        queryUri += "&$filterField=eq.$filterValue";
      }

      final request = await client.getUrl(Uri.parse(queryUri));
      request.headers.set('apikey', anonKey);
      request.headers.set('Authorization', 'Bearer $anonKey');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        client.close();
        return [];
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final list = jsonDecode(body);
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Supabase fetch error for $table: $e");
      return [];
    }
  }
}
