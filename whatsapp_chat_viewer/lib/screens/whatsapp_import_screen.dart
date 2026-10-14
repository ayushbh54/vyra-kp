import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/whatsapp_viewer_provider.dart';
import '../theme/whatsapp_theme.dart';

class WhatsAppImportScreen extends StatefulWidget {
  const WhatsAppImportScreen({super.key});

  @override
  State<WhatsAppImportScreen> createState() => _WhatsAppImportScreenState();
}

class _WhatsAppImportScreenState extends State<WhatsAppImportScreen> {
  File? _selectedFile;
  File? _selectedKeyFile;
  final TextEditingController _hexKeyController = TextEditingController();
  bool _isHexKeyValid = false;

  @override
  void initState() {
    super.initState();
    _hexKeyController.addListener(_validateHexKey);
  }

  @override
  void dispose() {
    _hexKeyController.removeListener(_validateHexKey);
    _hexKeyController.dispose();
    super.dispose();
  }

  void _validateHexKey() {
    final text = _hexKeyController.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final isValid = text.length == 64;
    if (isValid != _isHexKeyValid) {
      setState(() {
        _isHexKeyValid = isValid;
      });
    }
  }

  Future<void> _pickBackupFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select WhatsApp msgstore.db or .crypt14 / .crypt15 file',
      );
      if (files.isNotEmpty && files.first.path != null) {
        setState(() {
          _selectedFile = File(files.first.path!);
        });
      }
    } catch (e) {
      _showSnackbar('File picker error: $e');
    }
  }

  Future<void> _pickKeyFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select WhatsApp key file (158 bytes)',
      );
      if (files.isNotEmpty && files.first.path != null) {
        setState(() {
          _selectedKeyFile = File(files.first.path!);
        });
      }
    } catch (e) {
      _showSnackbar('Key picker error: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final cleaned = data!.text!.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      _hexKeyController.text = cleaned;
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WhatsAppTheme.cardBg,
      ),
    );
  }

  Future<void> _startDecryption() async {
    if (_selectedFile == null) {
      _showSnackbar('Please select WhatsApp database file first.');
      return;
    }

    final provider = context.read<WhatsAppViewerProvider>();
    final success = await provider.loadFromBackup(
      inputFile: _selectedFile!,
      hexKey: _hexKeyController.text.trim(),
      keyFile: _selectedKeyFile,
    );

    if (!success && mounted) {
      final error = provider.errorMessage ?? "Unknown error occurred";
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: WhatsAppTheme.appBarBg,
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: WhatsAppTheme.deletedColor),
              SizedBox(width: 8),
              Text('Decryption Failed', style: TextStyle(color: WhatsAppTheme.textPrimary)),
            ],
          ),
          content: Text(
            error,
            style: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: WhatsAppTheme.primaryGreen)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhatsAppViewerProvider>();

    return Scaffold(
      backgroundColor: WhatsAppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('WhatsApp Viewer & Decryptor'),
        backgroundColor: WhatsAppTheme.appBarBg,
        elevation: 0,
      ),
      body: provider.isLoading
          ? _buildLoadingState(provider)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderBanner(),
                  const SizedBox(height: 24),
                  _buildFilePickerSection(),
                  const SizedBox(height: 20),
                  _buildKeySection(),
                  const SizedBox(height: 28),
                  _buildDecryptButton(),
                  const SizedBox(height: 24),
                  _buildExportImportOption(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WhatsAppTheme.appBarBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WhatsAppTheme.dividerColor),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            backgroundColor: WhatsAppTheme.primaryGreen,
            radius: 26,
            child: Icon(Icons.security, color: Colors.black, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '100% Offline WhatsApp Decryptor',
                  style: TextStyle(
                    color: WhatsAppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Provide your child\'s com.whatsapp database and key to inspect chats and deleted messages securely on your device.',
                  style: TextStyle(
                    color: WhatsAppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePickerSection() {
    final fileName = _selectedFile?.path.split('/').last;
    final fileSizeMb = _selectedFile != null ? (_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WhatsAppTheme.appBarBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedFile != null ? WhatsAppTheme.primaryGreen : WhatsAppTheme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_open, color: WhatsAppTheme.primaryGreen, size: 20),
              SizedBox(width: 8),
              Text(
                '1. Select WhatsApp Backup or Database',
                style: TextStyle(
                  color: WhatsAppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Supported: msgstore.db.crypt14, msgstore.db.crypt15, msgstore.db (raw SQLite), or com.whatsapp.zip',
            style: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_selectedFile != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WhatsAppTheme.scaffoldBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: WhatsAppTheme.primaryGreen, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName ?? '',
                          style: const TextStyle(
                            color: WhatsAppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$fileSizeMb MB',
                          style: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: WhatsAppTheme.textSecondary, size: 20),
                    onPressed: () => setState(() => _selectedFile = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton.icon(
            onPressed: _pickBackupFile,
            icon: const Icon(Icons.file_upload_outlined, color: Colors.black),
            label: Text(
              _selectedFile == null ? 'Browse WhatsApp Backup File' : 'Change Selected File',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: WhatsAppTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeySection() {
    final hexLength = _hexKeyController.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WhatsAppTheme.appBarBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WhatsAppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_outlined, color: WhatsAppTheme.primaryGreen, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '2. Decryption Key (64-Hex or key file)',
                  style: TextStyle(
                    color: WhatsAppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hexLength > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isHexKeyValid ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$hexLength / 64',
                    style: TextStyle(
                      color: _isHexKeyValid ? WhatsAppTheme.primaryGreen : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 64-character hexadecimal key WhatsApp gave when enabling End-to-End Encrypted Backup, or select your key file.',
            style: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hexKeyController,
            style: const TextStyle(
              color: WhatsAppTheme.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. 7f3a9b4c81... (64 hex characters)',
              hintStyle: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 12),
              filled: true,
              fillColor: WhatsAppTheme.scaffoldBg,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste, color: WhatsAppTheme.primaryGreen),
                tooltip: 'Paste Key',
                onPressed: _pasteFromClipboard,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Divider(color: WhatsAppTheme.dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('OR', style: TextStyle(color: WhatsAppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11)),
              ),
              const Expanded(
                child: Divider(color: WhatsAppTheme.dividerColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickKeyFile,
            icon: const Icon(Icons.key, color: WhatsAppTheme.primaryGreen, size: 18),
            label: Text(
              _selectedKeyFile == null ? 'Select "key" File (158 bytes)' : 'Key: ${_selectedKeyFile!.path.split('/').last}',
              style: const TextStyle(color: WhatsAppTheme.textPrimary, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: WhatsAppTheme.dividerColor),
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecryptButton() {
    return ElevatedButton.icon(
      onPressed: _selectedFile == null ? null : _startDecryption,
      icon: const Icon(Icons.lock_open, color: Colors.black, size: 22),
      label: const Text(
        'Decrypt & View Chats',
        style: TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: WhatsAppTheme.primaryGreen,
        disabledBackgroundColor: WhatsAppTheme.dividerColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      ),
    );
  }

  Widget _buildExportImportOption() {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final files = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['txt', 'json'],
          );
          if (files.isNotEmpty && files.first.path != null && mounted) {
            final file = File(files.first.path!);
            final content = await file.readAsString();
            if (!mounted) return;
            final provider = context.read<WhatsAppViewerProvider>();
            await provider.importLocalChatDump(content, files.first.name);
          }
        },
        icon: const Icon(Icons.import_contacts, color: WhatsAppTheme.accentBlue, size: 18),
        label: const Text(
          'Or open WhatsApp exported chat (.txt / .json)',
          style: TextStyle(color: WhatsAppTheme.accentBlue, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildLoadingState(WhatsAppViewerProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(WhatsAppTheme.primaryGreen),
            ),
            const SizedBox(height: 24),
            Text(
              provider.loadingStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WhatsAppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: provider.loadingProgress > 0 ? provider.loadingProgress : null,
              backgroundColor: WhatsAppTheme.cardBg,
              valueColor: const AlwaysStoppedAnimation<Color>(WhatsAppTheme.primaryGreen),
            ),
            const SizedBox(height: 8),
            Text(
              '${(provider.loadingProgress * 100).toInt()}%',
              style: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
