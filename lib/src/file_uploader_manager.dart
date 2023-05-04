import 'extensions.dart';
import 'file_uploader.dart';
import 'utils.dart';

import 'package:cross_file/cross_file.dart' show XFile;

class TusFileUploaderManager {
  final String baseUrl;
  final int? timeout;
  final _cache = <String, TusFileUploader>{};

  TusFileUploaderManager(
    this.baseUrl, {
    this.timeout,
  });

  Future<void> uploadFile({
    required String localFilePath,
    String? customScheme,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    Map<String, String> metadata = const {},
    Map<String, String> headers = const {},
    bool failOnLostConnection = false,
  }) async {
    final xFile = XFile(localFilePath);
    TusFileUploader? uploader = _cache[localFilePath];
    String? uploadUrl;
    if (uploader == null) {
      final totalBytes = await xFile.length();
      final uploadMetadata = xFile.generateMetadata(originalMetadata: metadata);
      final resultHeaders = Map<String, String>.from(headers)
        ..addAll({
          "Tus-Resumable": tusVersion,
          "Upload-Metadata": uploadMetadata,
          "Upload-Length": "$totalBytes",
        });
      uploader = TusFileUploader.init(
        path: localFilePath,
        baseUrl: Uri.parse(baseUrl + (customScheme ?? '')),
        headers: resultHeaders,
        timeout: timeout,
        failOnLostConnection: failOnLostConnection,
        progressCallback: progressCallback,
        completeCallback: (filePath, uploadUrl) async {
          completeCallback?.call(filePath, uploadUrl);
          _removeFileWithPath(localFilePath);
        },
        failureCallback: (filePath, message) async {
          failureCallback?.call(filePath, message);
          _removeFileWithPath(localFilePath);
        },
      );
      _cache[localFilePath] = uploader;
      uploadUrl = await uploader.setupUploadUrl();
    }
    if (uploadUrl != null) {
      await uploader.upload(
        headers: headers,
      );
    }
  }

  void pauseAllUploading() {
    for (final uploader in _cache.values) {
      uploader.pause();
    }
  }

  void resumeAllUploading() {
    for (final uploader in _cache.values) {
      uploader.upload();
    }
  }

  Future<void> _removeFileWithPath(String path) async {
    _cache.remove(path);
  }
}
