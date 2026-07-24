import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'encryption_service.dart';

class EvidenceVaultService {
  final EncryptionService _encryptionService;
  final Uuid _uuid;
  final Map<String, String> _payloadCache = <String, String>{};
  final Map<String, Map<String, dynamic>> _metadataCache =
      <String, Map<String, dynamic>>{};

  EvidenceVaultService(this._encryptionService) : _uuid = const Uuid();

  Future<Directory> _storageRoot() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      return _fallbackStorageDirectory();
    } on UnsupportedError {
      return _fallbackStorageDirectory();
    }
  }

  Future<Directory> _fallbackStorageDirectory() async {
    final basePath = Directory.systemTemp.path;

    final dir = Directory(p.join(basePath, '.safeher'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _vaultDirectory() async {
    final docs = await _storageRoot();
    final vault = Directory(p.join(docs.path, 'safeher_evidence_vault'));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    return vault;
  }

  Future<String> saveEncryptedEvidence({
    required Uint8List bytes,
    required String extension,
    required Map<String, dynamic> metadata,
  }) async {
    final id = _uuid.v4();
    final blob = await _encryptionService.encryptBytes(bytes);

    if (kIsWeb) {
      _payloadCache[id] = jsonEncode(blob.toJson());
      _metadataCache[id] = {
        'id': id,
        'extension': extension,
        'stored_at': DateTime.now().toIso8601String(),
        'metadata': metadata,
      };
      return id;
    }

    final vault = await _vaultDirectory();

    final payloadPath = p.join(vault.path, '$id.enc');
    final metadataPath = p.join(vault.path, '$id.meta.json');

    await File(payloadPath).writeAsString(jsonEncode(blob.toJson()));
    await File(metadataPath).writeAsString(
      jsonEncode({
        'id': id,
        'extension': extension,
        'stored_at': DateTime.now().toIso8601String(),
        'metadata': metadata,
      }),
    );

    return id;
  }

  Future<Uint8List?> readDecryptedEvidence(String evidenceId) async {
    if (kIsWeb) {
      final raw = _payloadCache[evidenceId];
      if (raw == null) {
        return null;
      }

      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final blob = EncryptedBlob.fromJson(jsonMap);
      return _encryptionService.decryptBytes(blob);
    }

    final vault = await _vaultDirectory();
    final payloadPath = p.join(vault.path, '$evidenceId.enc');
    final payloadFile = File(payloadPath);

    if (!await payloadFile.exists()) {
      return null;
    }

    final raw = await payloadFile.readAsString();
    final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    final blob = EncryptedBlob.fromJson(jsonMap);
    return _encryptionService.decryptBytes(blob);
  }

  Future<Map<String, dynamic>?> readEvidenceMetadata(String evidenceId) async {
    if (kIsWeb) {
      return _metadataCache[evidenceId];
    }

    final vault = await _vaultDirectory();
    final metadataPath = p.join(vault.path, '$evidenceId.meta.json');
    final metadataFile = File(metadataPath);

    if (!await metadataFile.exists()) {
      return null;
    }

    final raw = await metadataFile.readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
