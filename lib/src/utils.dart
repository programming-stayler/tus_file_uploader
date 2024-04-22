const tusVersion = "1.0.0";

typedef UploadingProgressCallback = Future<void> Function(String filePath, double progress);
typedef UploadingCompleteCallback = Future<void> Function(String filePath, String uploadUrl);
typedef UploadingFailedCallback = Future<void> Function(String filePath, String message);