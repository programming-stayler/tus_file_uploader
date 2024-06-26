class ProtocolException implements Exception {
  final int statusCode;
  final String? message;

  ProtocolException(
    this.statusCode, {
    this.message,
  });

  @override
  String toString() =>
      'ProtocolException: unexpected status code ($statusCode) while uploading chunk\n$message';
}

class MissingUploadOffsetException implements Exception {
  final String? message;

  MissingUploadOffsetException({
    this.message,
  });

  @override
  String toString() =>
      "MissingUploadOffsetException: ${message ?? 'response for resuming upload is empty'}";
}

class ChunkUploadFailedException implements Exception {
  @override
  String toString() =>
      'ChunkUploadFailedException: response to PATCH request contains no or invalid Upload-Offset header';
}

class MissingUploadUriException implements Exception {
  @override
  String toString() =>
      'MissingUploadUriException: missing upload Uri in response for creating upload';
}

class UnauthorizedException implements Exception {
  final String? message;

  UnauthorizedException({
    this.message,
  });

  @override
  String toString() => 'UnauthorizedException: ${message ?? "Failed to authorize"}';
}

class InternalServerErrorException implements Exception {
  final String? message;

  InternalServerErrorException({
    this.message,
  });

  @override
  String toString() => 'InternalServerErrorException: ${message ?? ""}';
}
