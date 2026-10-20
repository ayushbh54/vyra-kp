import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyra_p/services/audio_playback_service.dart';

void main() {
  group('Google Drive Direct Streaming & Playback Verification Suite', () {
    test('1. AudioPlaybackService properly normalizes Google Drive URLs to direct byte-range endpoint', () {
      const driveUcUrl = 'https://drive.google.com/uc?export=download&id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_';
      const driveFileUrl = 'https://drive.google.com/file/d/1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_/view';
      const driveDirectUrl = 'https://drive.usercontent.google.com/download?id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_&export=download';

      expect(
        AudioPlaybackService.normalizeAudioUrl(driveUcUrl),
        'https://drive.usercontent.google.com/download?id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_&export=download',
      );

      expect(
        AudioPlaybackService.normalizeAudioUrl(driveFileUrl),
        'https://drive.usercontent.google.com/download?id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_&export=download',
      );

      expect(
        AudioPlaybackService.normalizeAudioUrl(driveDirectUrl),
        'https://drive.usercontent.google.com/download?id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_&export=download',
      );
    });

    test('2. Live Network Test: Ambient Audio stream returns HTTP 206 Partial Content with byte ranges', () async {
      final client = HttpClient();
      final url = Uri.parse('https://drive.usercontent.google.com/download?id=1rAfIrnT8DL4YBdD-if96bZjwa5QviGsR&export=download');
      
      final req = await client.getUrl(url);
      req.headers.set('Range', 'bytes=0-1024');
      final res = await req.close();

      expect(res.statusCode, equals(206), reason: 'Audio stream must support HTTP 206 Partial Content for instant seeking');
      expect(res.headers.value('content-type'), contains('audio/mp4'));
      expect(res.headers.value('accept-ranges'), equals('bytes'));
      client.close();
    });

    test('3. Live Network Test: Call Recording stream returns HTTP 206 Partial Content with byte ranges', () async {
      final client = HttpClient();
      final url = Uri.parse('https://drive.usercontent.google.com/download?id=1sOX3Z8pOEjPsSoqjvDAlp-Kb6ct8E24_&export=download');
      
      int statusCode = 0;
      String? contentType;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final req = await client.getUrl(url);
          req.headers.set('Range', 'bytes=0-1024');
          final res = await req.close();
          statusCode = res.statusCode;
          contentType = res.headers.value('content-type');
          await res.drain();
          if (statusCode == 206) break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      expect(statusCode, equals(206), reason: 'Call recording stream must support HTTP 206 Partial Content');
      expect(contentType, contains('audio/mp4'));
      client.close();
    });

    test('4. Live Network Test: Snap & Screenshot images return HTTP 200 with image/jpeg from Drive CDN', () async {
      final client = HttpClient();
      final url = Uri.parse('https://lh3.googleusercontent.com/d/1WerrOMyB43wMLtvbFHymgfwVZBtTkYhM');
      
      final req = await client.getUrl(url);
      final res = await req.close();

      expect(res.statusCode, equals(200), reason: 'Snap images must return HTTP 200 from high-speed CDN without auth redirect');
      expect(res.headers.value('content-type'), contains('image/'));
      expect(res.headers.value('access-control-allow-origin'), equals('*'));
      client.close();
    });
  });
}
