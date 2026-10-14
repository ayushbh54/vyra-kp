import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/whatsapp_conversation.dart';
import '../models/whatsapp_message.dart';
import '../services/local_backup_importer.dart';
import '../services/whatsapp_crypt_service.dart';
import '../services/whatsapp_sqlite_service.dart';

class WhatsAppViewerProvider with ChangeNotifier {
  final WhatsAppSqliteService _sqliteService = WhatsAppSqliteService();

  bool _isLoading = false;
  double _loadingProgress = 0.0;
  String _loadingStatus = "";
  String? _errorMessage;

  List<WhatsAppConversation> _allConversations = [];
  List<WhatsAppConversation> _conversations = [];
  List<WhatsAppMessage> _messages = [];
  List<WhatsAppMessage> _allDeletedMessages = [];
  WhatsAppConversation? _selectedConversation;
  String _searchQuery = "";

  bool get isLoading => _isLoading;
  double get loadingProgress => _loadingProgress;
  String get loadingStatus => _loadingStatus;
  String? get errorMessage => _errorMessage;
  bool get isLoaded => _sqliteService.isOpen || _allConversations.isNotEmpty;

  List<WhatsAppConversation> get conversations => _conversations;
  List<WhatsAppMessage> get messages => _messages;
  List<WhatsAppMessage> get allDeletedMessages => _allDeletedMessages;
  WhatsAppConversation? get selectedConversation => _selectedConversation;
  String get searchQuery => _searchQuery;
  int get totalDeletedCount => _allDeletedMessages.length;

  WhatsAppViewerProvider() {
    _tryRestorePreviousSession();
  }

  Future<void> _tryRestorePreviousSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPath = prefs.getString('last_decrypted_db_path');
      if (lastPath != null) {
        final file = File(lastPath);
        if (await file.exists()) {
          await openDatabaseDirectly(file);
        }
      }
    } catch (_) {}
  }

  /// Open and decrypt WhatsApp backup (msgstore.db.crypt14 / crypt15 / raw msgstore.db / zip)
  Future<bool> loadFromBackup({
    required File inputFile,
    String? hexKey,
    File? keyFile,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _loadingProgress = 0.05;
    _loadingStatus = "Starting WhatsApp decryption...";
    notifyListeners();

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${appDir.path}/whatsapp_vault');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final decryptedSqliteFile = await WhatsAppCryptService.prepareSqliteDatabase(
        inputFile: inputFile,
        outputDir: outputDir,
        hexKey: hexKey,
        keyFile: keyFile,
        onProgress: (status, progress) {
          _loadingStatus = status;
          _loadingProgress = progress;
          notifyListeners();
        },
      );

      // Open SQLite database
      _loadingStatus = "Indexing WhatsApp chats and contacts...";
      _loadingProgress = 0.85;
      notifyListeners();

      await _sqliteService.openDatabaseFile(decryptedSqliteFile);

      // Fetch chats
      _allConversations = await _sqliteService.fetchConversations();
      _conversations = List.from(_allConversations);

      // Fetch all deleted messages
      _loadingStatus = "Scanning deleted messages...";
      _loadingProgress = 0.95;
      notifyListeners();

      _allDeletedMessages = await _sqliteService.fetchAllDeletedMessages();

      // Remember session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_decrypted_db_path', decryptedSqliteFile.path);

      _loadingProgress = 1.0;
      _loadingStatus = "Successfully loaded ${_allConversations.length} conversations!";
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('FormatException: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Directly open an already decrypted or raw SQLite database
  Future<bool> openDatabaseDirectly(File sqliteFile) async {
    _isLoading = true;
    _errorMessage = null;
    _loadingStatus = "Opening SQLite database...";
    notifyListeners();

    try {
      await _sqliteService.openDatabaseFile(sqliteFile);
      _allConversations = await _sqliteService.fetchConversations();
      _conversations = List.from(_allConversations);
      _allDeletedMessages = await _sqliteService.fetchAllDeletedMessages();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_decrypted_db_path', sqliteFile.path);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = "Failed to open SQLite database: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Import local exported chat file (.txt or .json dump)
  Future<bool> importLocalChatDump(String fileContent, String fileName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final isJson = fileName.toLowerCase().endsWith('.json') || fileContent.trim().startsWith('[');
      List<WhatsAppMessage> imported;
      if (isJson) {
        imported = LocalBackupImporter.parseJsonDump(fileContent);
      } else {
        imported = LocalBackupImporter.parseExportedChatTxt(fileContent, defaultContact: fileName);
      }

      if (imported.isEmpty) {
        throw const FormatException("No valid WhatsApp messages found in the file.");
      }

      final convId = "export_${DateTime.now().millisecondsSinceEpoch}";
      final newConv = WhatsAppConversation(
        id: convId,
        name: fileName.replaceAll('.txt', '').replaceAll('.json', '').replaceAll('WhatsApp Chat with ', ''),
        phoneNumber: '',
        isGroup: false,
        lastMessageText: imported.last.text,
        lastMessageTime: imported.last.timestamp,
        deletedCount: imported.where((m) => m.isDeletedBySender).length,
      );

      _allConversations = [newConv, ..._allConversations];
      _conversations = List.from(_allConversations);
      _allDeletedMessages = [
        ...imported.where((m) => m.isDeletedBySender),
        ..._allDeletedMessages,
      ];
      _messages = imported;
      _selectedConversation = newConv;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Select conversation to view messages
  Future<void> selectConversation(WhatsAppConversation conv) async {
    _selectedConversation = conv;
    _messages = [];
    notifyListeners();

    if (_sqliteService.isOpen) {
      _messages = await _sqliteService.fetchMessagesForConversation(conv.id);
    }
    notifyListeners();
  }

  /// Filter conversations with search query
  void search(String query) {
    _searchQuery = query.toLowerCase().trim();
    if (_searchQuery.isEmpty) {
      _conversations = List.from(_allConversations);
    } else {
      _conversations = _allConversations.where((c) {
        return c.contactName.toLowerCase().contains(_searchQuery) ||
            c.phoneNumber.contains(_searchQuery) ||
            c.lastMessage.text.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    notifyListeners();
  }

  /// Close and unlink current database
  Future<void> clearDatabase() async {
    await _sqliteService.closeDatabase();
    _allConversations = [];
    _conversations = [];
    _messages = [];
    _allDeletedMessages = [];
    _selectedConversation = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_decrypted_db_path');

    notifyListeners();
  }
}
