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

  Future<List<Map<String, dynamic>>> fetchTable(
    String table, {
    String? filterField,
    String? filterValue,
    String? greaterThanField,
    dynamic greaterThanValue,
    Map<String, String>? extraFilters,
    String? order,
    int? limit,
  }) async {
    if (!isConfigured) return [];

    try {
      final allRows = <Map<String, dynamic>>[];
      int offset = 0;

      while (true) {
        final remaining = limit != null ? (limit - allRows.length) : 1000;
        if (remaining <= 0) break;
        final pageSize = remaining < 1000 ? remaining : 1000;

        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        var queryUri = "$supabaseUrl/rest/v1/$table?select=*";
        if (filterField != null && filterValue != null) {
          queryUri += "&$filterField=eq.${Uri.encodeQueryComponent(filterValue)}";
        }
        if (greaterThanField != null && greaterThanValue != null) {
          queryUri += "&$greaterThanField=gt.${Uri.encodeQueryComponent(greaterThanValue.toString())}";
        }
        if (extraFilters != null) {
          extraFilters.forEach((k, v) {
            queryUri += "&$k=eq.${Uri.encodeQueryComponent(v)}";
          });
        }
        if (order != null) {
          queryUri += "&order=$order";
        }
        queryUri += "&limit=$pageSize&offset=$offset";

        final request = await client.getUrl(Uri.parse(queryUri));
        request.headers.set('apikey', anonKey);
        request.headers.set('Authorization', 'Bearer $anonKey');

        final response = await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          client.close();
          break;
        }

        final body = await response.transform(utf8.decoder).join();
        client.close();

        final list = jsonDecode(body);
        if (list is List) {
          final batch = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          allRows.addAll(batch);
          if (batch.length < pageSize || (limit != null && allRows.length >= limit)) {
            break;
          }
          offset += pageSize;
        } else {
          break;
        }
      }
      return allRows;
    } catch (e) {
      debugPrint("Supabase fetch error for $table: $e");
      return [];
    }
  }

  /// Upserts a record into Supabase PostgreSQL table with merge-on-duplicate
  Future<bool> upsertRecord(String table, Map<String, dynamic> record) async {
    if (!isConfigured) return false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.postUrl(Uri.parse("$supabaseUrl/rest/v1/$table"));
      request.headers.set('apikey', anonKey);
      request.headers.set('Authorization', 'Bearer $anonKey');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Prefer', 'resolution=merge-duplicates');
      request.write(jsonEncode([record]));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      client.close();
      return success;
    } catch (e) {
      debugPrint("Error upserting to Supabase $table: $e");
      return false;
    }
  }

  /// Dispatches remote command to child via Supabase commands queue
  Future<bool> sendCommand(String childId, String action, [Map<String, dynamic>? payload]) async {
    if (!isConfigured) return false;

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.postUrl(Uri.parse("$supabaseUrl/rest/v1/commands"));
      request.headers.set('apikey', anonKey);
      request.headers.set('Authorization', 'Bearer $anonKey');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Prefer', 'return=minimal');

      final body = jsonEncode({
        'id': 'cmd_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}',
        'child_id': childId,
        'action': action,
        'payload': payload ?? {},
        'status': 'PENDING',
      });
      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 10));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      client.close();
      return success;
    } catch (e) {
      debugPrint("Error sending command to Supabase: $e");
      return false;
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
