import 'uploading_model.dart';

const tusVersion = "1.0.0";

typedef UploadingProgressCallback = Future<void> Function(UploadingModel uploadingModel, double progress);
typedef UploadingCompleteCallback = Future<void> Function(UploadingModel uploadingModel, String uploadUrl);
typedef UploadingFailedCallback = Future<void> Function(UploadingModel uploadingModel, String message);