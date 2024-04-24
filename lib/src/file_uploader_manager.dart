import 'extensions.dart';
import 'file_uploader.dart';
import 'utils.dart';
import 'uploading_model.dart';

import 'package:cross_file/cross_file.dart' show XFile;

class TusFileUploaderManager {
  final String baseUrl;
  final int? timeout;
  final _cache = <int, TusFileUploader>{};

  TusFileUploaderManager(
    this.baseUrl, {
    this.timeout,
  });

  Future<void> uploadFile({
    required UploadingModel uploadingModel,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    UploadingFailedCallback? authCallback,
    Map<String, String> metadata = const {},
    Map<String, String> headers = const {},
    bool failOnLostConnection = false,
  }) async {
    final xFile = XFile(uploadingModel.path);
    TusFileUploader? uploader = _cache[uploadingModel.id];
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
      uploader = TusFileUploader(
        uploadingModel: uploadingModel,
        baseUrl: baseUrl,
        headers: resultHeaders,
        timeout: timeout,
        failOnLostConnection: failOnLostConnection,
        progressCallback: progressCallback,
        completeCallback: (uploadingModel, uploadUrl) async {
          completeCallback?.call(uploadingModel, uploadUrl);
          _removeFileWithPath(uploadingModel.id);
        },
        failureCallback: (uploadingModel, message) async {
          failureCallback?.call(uploadingModel, message);
          _removeFileWithPath(uploadingModel.id);
        },
        authCallback: (uploadingModel, message) async {
          authCallback?.call(uploadingModel, message);
          _removeFileWithPath(uploadingModel.id);
        }
      );
      _cache[uploadingModel.id] = uploader;
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

  Future<void> _removeFileWithPath(int id) async {
    _cache.remove(id);
  }
}
