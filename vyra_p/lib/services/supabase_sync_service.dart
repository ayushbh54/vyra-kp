import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SupabaseSyncService {
  static const String defaultUrl = "https://wtlqlkkduescumpggttm.supabase.co";
  static const String defaultAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0";

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

  /// Purges past records from Supabase Cloud tables (chats, calls, notifications)
  /// for a specific child or all records, to free up cloud storage.
  /// Does NOT affect parent phone's local offline persistence cache!
  Future<bool> purgeChildCloudHistory(String childId) async {
    if (!isConfigured) return false;

    bool allSuccess = true;
    final tables = ['chats', 'calls', 'notifications'];

    for (final table in tables) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
        final deleteUri = "$supabaseUrl/rest/v1/$table?child_id=eq.$childId";

        final request = await client.deleteUrl(Uri.parse(deleteUri));
        request.headers.set('apikey', anonKey);
        request.headers.set('Authorization', 'Bearer $anonKey');

        final response = await request.close().timeout(const Duration(seconds: 10));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          allSuccess = false;
        }
        client.close();
      } catch (e) {
        debugPrint("Error purging Supabase table $table: $e");
        allSuccess = false;
      }
    }
    return allSuccess;
  }
}
