import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';

/// Service responsible for decrypting WhatsApp databases (.crypt14, .crypt15, .crypt12)
/// and verifying raw unencrypted msgstore.db or ZIP archives.
class WhatsAppCryptService {
  static const List<int> sqliteMagic = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
    0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
  ];

  static const List<int> zipMagic = [0x50, 0x4B, 0x03, 0x04];

  /// Checks if file is already an unencrypted SQLite database
  static bool isUnencryptedSqlite(Uint8List bytes) {
    if (bytes.length < 16) return false;
    for (int i = 0; i < 16; i++) {
      if (bytes[i] != sqliteMagic[i]) return false;
    }
    return true;
  }

  /// Checks if file is a ZIP archive
  static bool isZipArchive(Uint8List bytes) {
    if (bytes.length < 4) return false;
    for (int i = 0; i < 4; i++) {
      if (bytes[i] != zipMagic[i]) return false;
    }
    return true;
  }

  /// Convert 64-character hex string into 32-byte key.
  /// If user pasted the hex dump of a 156/158-byte key file (>124 hex chars),
  /// extracts the 32-byte AES key from offset 30..62 (hex chars 60..124).
  static Uint8List parseHexKey(String hexString) {
    String cleaned = hexString.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length >= 124) {
      // Hex dump of key file. Offset 30 bytes = hex char 60, length 32 bytes = 64 hex chars
      cleaned = cleaned.substring(60, 124);
    }
    if (cleaned.length != 64) {
      throw FormatException(
        'Key must be exactly 64 hexadecimal characters (32 bytes). Found ${cleaned.length} chars.',
      );
    }
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      final hexByte = cleaned.substring(i * 2, i * 2 + 2);
      bytes[i] = int.parse(hexByte, radix: 16);
    }
    return bytes;
  }

  /// Extract root key from WhatsApp local key file (from /data/data/com.whatsapp/files/key)
  /// Supports 32-byte raw keys, and 156/158/160-byte standard WhatsApp key files.
  static Uint8List parseKeyFile(Uint8List fileBytes) {
    if (fileBytes.length == 32) {
      return fileBytes; // Raw 32-byte key
    }
    if (fileBytes.length >= 62) {
      // In standard WhatsApp key files (156 bytes, 158 bytes, etc.),
      // offset 30 to 62 contains the 32-byte AES key
      return fileBytes.sublist(30, 62);
    }
    throw FormatException(
      'Unsupported key file size: ${fileBytes.length} bytes. Expected 32 bytes or >= 62 bytes (e.g. 156/158 bytes).',
    );
  }

  /// Derives the actual 32-byte AES-GCM encryption key from the root key
  /// according to WhatsApp Crypt15 HKDF specification:
  /// privatekey = HMAC-SHA256(key = 32 zero bytes, msg = root_key)
  /// output_key = HMAC-SHA256(key = privatekey, msg = "backup encryption" + 0x01)
  static Uint8List deriveCrypt15Key(Uint8List rootKey) {
    final zeroSeed = List<int>.filled(32, 0);
    final hmacExtractor = crypto_pkg.Hmac(crypto_pkg.sha256, zeroSeed);
    final privateKey = hmacExtractor.convert(rootKey).bytes;

    final message = utf8.encode("backup encryption");
    final hmacExpander = crypto_pkg.Hmac(crypto_pkg.sha256, privateKey);
    final dataToSign = <int>[...message, 0x01];
    final derivedKey = hmacExpander.convert(dataToSign).bytes;

    return Uint8List.fromList(derivedKey.sublist(0, 32));
  }

  /// Main method: Decrypts WhatsApp database or extracts from ZIP/raw SQLite.
  /// Returns the path to the decrypted/ready SQLite file.
  static Future<File> prepareSqliteDatabase({
    required File inputFile,
    required Directory outputDir,
    String? hexKey,
    File? keyFile,
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call("Reading input file...", 0.1);
    final fileBytes = await inputFile.readAsBytes();

    // 1. Direct unencrypted SQLite check
    if (isUnencryptedSqlite(fileBytes)) {
      onProgress?.call("Unencrypted SQLite database detected", 0.9);
      final destFile = File('${outputDir.path}/msgstore_decrypted.db');
      await inputFile.copy(destFile.path);
      return destFile;
    }

    // 2. ZIP archive check (some backups contain msgstore.db in ZIP)
    if (isZipArchive(fileBytes)) {
      onProgress?.call("Extracting ZIP archive...", 0.4);
      final archive = ZipDecoder().decodeBytes(fileBytes);
      for (final archiveFile in archive) {
        if (archiveFile.name.endsWith('msgstore.db')) {
          final destFile = File('${outputDir.path}/msgstore_decrypted.db');
          await destFile.writeAsBytes(archiveFile.content as List<int>);
          onProgress?.call("Extracted msgstore.db from ZIP", 0.9);
          return destFile;
        }
      }
    }

    // 3. Resolve key for decryption
    onProgress?.call("Parsing encryption key...", 0.2);
    Uint8List? rawKey;
    if (hexKey != null && hexKey.trim().isNotEmpty) {
      rawKey = parseHexKey(hexKey);
    } else if (keyFile != null && await keyFile.exists()) {
      final keyBytes = await keyFile.readAsBytes();
      rawKey = parseKeyFile(keyBytes);
    }

    if (rawKey == null) {
      throw const FormatException(
        "File is encrypted, but no decryption key was provided. Please enter the 64-character hex key or select the key file.",
      );
    }

    // 4. Decrypt Crypt12 / Crypt13 / Crypt14 / Crypt15
    onProgress?.call("Decrypting backup with AES-256...", 0.4);
    final decryptedBytes = await _decryptCryptPayload(fileBytes, rawKey);

    onProgress?.call("Decompressing zlib stream...", 0.7);
    final decompressed = _decompressZlib(decryptedBytes);

    if (!isUnencryptedSqlite(decompressed)) {
      // If it's a zip inside
      if (isZipArchive(decompressed)) {
        final archive = ZipDecoder().decodeBytes(decompressed);
        for (final archiveFile in archive) {
          if (archiveFile.name.endsWith('msgstore.db')) {
            final destFile = File('${outputDir.path}/msgstore_decrypted.db');
            await destFile.writeAsBytes(archiveFile.content as List<int>);
            return destFile;
          }
        }
      }
      throw const FormatException(
        "Decryption finished, but output does not match SQLite signature. Key or offset may be incorrect.",
      );
    }

    final destFile = File('${outputDir.path}/msgstore_decrypted.db');
    await destFile.writeAsBytes(decompressed);
    onProgress?.call("Ready! SQLite database verified", 1.0);
    return destFile;
  }

  /// Internal AES-GCM & AES-CBC decryption with Crypt12/Crypt14 raw key & Crypt15 derived key
  static Future<Uint8List> _decryptCryptPayload(Uint8List data, Uint8List rootKey) async {
    final derivedKey = deriveCrypt15Key(rootKey);
    // Try raw key first (for local Crypt12/13/14 backups), then derived key (for Crypt15)
    final keysToTry = <Uint8List>[rootKey, derivedKey];

    // Priority candidate offsets:
    // 1. Classic Crypt12 / Crypt14: IV at 51..67, data starts at 67
    // 2. Crypt14 standard: IV at 67..83, data starts at 191
    // 3. Crypt14 alternate: IV at 66..82, data starts at 190
    // 4. Protobuf header offset
    final protobufOffset = _extractProtobufHeaderOffset(data);
    final candidateOffsets = <int>[
      67, 191, 190,
      if (protobufOffset > 0 && protobufOffset < data.length - 64) protobufOffset,
      128, 64, 32, 16, 0
    ].where((offset) => offset > 0 && offset < data.length - 64).toSet().toList();

    for (final key in keysToTry) {
      for (final dataOffset in candidateOffsets) {
        try {
          Uint8List iv;
          if (dataOffset == 67 && data.length >= 67) {
            iv = data.sublist(51, 67);
          } else if (dataOffset == 191 && data.length >= 83) {
            iv = data.sublist(67, 83);
          } else if (dataOffset == 190 && data.length >= 82) {
            iv = data.sublist(66, 82);
          } else if (dataOffset >= 16) {
            iv = data.sublist(dataOffset - 16, dataOffset);
          } else {
            iv = Uint8List(16);
          }

          final ciphertextWithTag = data.sublist(dataOffset);

          // 1. Try AES-GCM
          final gcmResult = await _tryAesGcmDecrypt(ciphertextWithTag, key, iv);
          if (gcmResult != null) return gcmResult;

          // 2. Try AES-CBC (for Crypt12/14 variants that use CBC)
          final cbcResult = await _tryAesCbcDecrypt(ciphertextWithTag, key, iv);
          if (cbcResult != null) return cbcResult;
        } catch (_) {
          // continue trying next candidate
        }
      }
    }

    // Direct fallback for byte 67 IV and byte 191 data
    if (data.length > 220) {
      for (final key in keysToTry) {
        try {
          final iv = data.sublist(67, 83);
          final ciphertext = data.sublist(191);
          final res = await _tryAesGcmDecrypt(ciphertext, key, iv);
          if (res != null) return res;
          final resCbc = await _tryAesCbcDecrypt(ciphertext, key, iv);
          if (resCbc != null) return resCbc;
        } catch (_) {}
      }
    }

    throw const FormatException(
      "Failed to decrypt backup. Check if the key (64-hex or 156/158-byte key file) matches this backup file.",
    );
  }

  static Future<Uint8List?> _tryAesCbcDecrypt(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List iv,
  ) async {
    try {
      final algorithm = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = SecretKey(key);
      final secretBox = SecretBox(
        ciphertext,
        nonce: iv,
        mac: Mac.empty,
      );
      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  static int _extractProtobufHeaderOffset(Uint8List data) {
    if (data.length < 4) return 0;
    // Varint decode first byte(s)
    int shift = 0;
    int size = 0;
    int cursor = 0;
    while (cursor < data.length && cursor < 5) {
      final b = data[cursor++];
      size |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return cursor + size;
  }

  static Future<Uint8List?> _tryAesGcmDecrypt(
    Uint8List ciphertextWithTag,
    Uint8List key,
    Uint8List iv,
  ) async {
    try {
      final algorithm = AesGcm.with256bits(nonceLength: 16);
      final secretKey = SecretKey(key);

      // WhatsApp appends 16-byte tag (and sometimes 16-byte checksum)
      // Check if tag is last 16 bytes or last 32..16 bytes
      Uint8List cipherPayload;
      Uint8List macBytes;

      if (ciphertextWithTag.length > 32) {
        cipherPayload = ciphertextWithTag.sublist(0, ciphertextWithTag.length - 32);
        macBytes = ciphertextWithTag.sublist(ciphertextWithTag.length - 32, ciphertextWithTag.length - 16);
      } else if (ciphertextWithTag.length > 16) {
        cipherPayload = ciphertextWithTag.sublist(0, ciphertextWithTag.length - 16);
        macBytes = ciphertextWithTag.sublist(ciphertextWithTag.length - 16);
      } else {
        return null;
      }

      final secretBox = SecretBox(
        cipherPayload,
        nonce: iv,
        mac: Mac(macBytes),
      );

      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _decompressZlib(Uint8List compressed) {
    try {
      final decompressed = ZLibDecoder().decodeBytes(compressed);
      return Uint8List.fromList(decompressed);
    } catch (_) {
      // If already uncompressed
      return compressed;
    }
  }
}
