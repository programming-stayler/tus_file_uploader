import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:async/async.dart';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'uploading_model.dart';
import 'utils.dart';
import 'exceptions.dart';
import 'extensions.dart';

class TusFileUploader {
  static const _kb = 1024; // ! KB
  static const _defaultChunkSize = 16 * _kb; // 16 KB
  static const _minChunkSize = 1 * _kb;
  final _client = http.Client();

  final UploadingModel _uploadingModel;

  String? get _uploadUrl => _uploadingModel.uploadUrl;
  CancelableOperation? _currentOperation;

  final XFile _file;
  final Duration _timeout;
  int _currentChunkSize;
  final int _optimalChunkSendTime;
  final Logger _logger;

  final UploadingProgressCallback? progressCallback;
  final UploadingCompleteCallback? completeCallback;
  final UploadingFailedCallback? failureCallback;
  final UploadingFailedCallback? authCallback;
  final UploadingFailedCallback? serverErrorCallback;
  final Map<String, String> headers;
  final bool failOnLostConnection;
  final String baseUrl;

  bool uploadingIsPaused = false;

  TusFileUploader({
    required UploadingModel uploadingModel,
    required this.baseUrl,
    required this.headers,
    required this.failOnLostConnection,
    Level loggerLevel = Level.off,
    this.progressCallback,
    this.completeCallback,
    this.failureCallback,
    this.serverErrorCallback,
    this.authCallback,
    int? optimalChunkSendTime,
    int? timeout,
  })  : _uploadingModel = uploadingModel,
        _currentChunkSize = _defaultChunkSize,
        _file = XFile(uploadingModel.path),
        _timeout = Duration(seconds: timeout ?? 3),
        _optimalChunkSendTime = optimalChunkSendTime ?? 1000,
        _logger = Logger(
          level: loggerLevel,
          printer: PrettyPrinter(
            methodCount: 0,
          ),
        ) {
    _logger.d(
      "INIT FILE UPLOADER\n=> File path: ${uploadingModel.path}\n=> Upload url: ${uploadingModel.uploadUrl}\n=> Timeout: $_timeout\n=> OCHST: $_optimalChunkSendTime\n=> Headers: $headers",
    );
  }

  Future<String?> setupUploadUrl() async {
    if (_uploadUrl != null) {
      return _uploadUrl!;
    }
    try {
      _currentOperation = CancelableOperation<String>.fromFuture(
        _client
            .setupUploadUrl(
              baseUrl: baseUrl + (_uploadingModel.customScheme ?? ''),
              headers: headers,
              timeout: _timeout,
            )
            .timeout(
              _timeout,
              onTimeout: () => throw TimeoutException("Get current offset timeout"),
            ),
      );
      _uploadingModel.uploadUrl = await _currentOperation!.value;
      _logger.d(
        "SETUP UPLOAD URL\n=> Url: $_uploadUrl",
      );
      return _uploadUrl;
    } on UnauthorizedException catch (e) {
      _logger.e("$e");
      await authCallback?.call(_uploadingModel, e.toString());
      return null;
    } on InternalServerErrorException catch (e) {
      _logger.e("$e");
      await serverErrorCallback?.call(_uploadingModel, e.toString());
      return null;
    } catch (e) {
      _logger.e("$e");
      await failureCallback?.call(_uploadingModel, e.toString());
      return null;
    }
  }

  void pause() {
    uploadingIsPaused = true;
    _currentChunkSize = _defaultChunkSize;
    _currentOperation?.cancel();
  }

  Future<void> upload({
    Map<String, String> headers = const {},
  }) async {
    uploadingIsPaused = false;
    _currentOperation = CancelableOperation.fromFuture(() async {
      try {
        final uploadUrl = _uploadUrl;
        if (uploadUrl == null) {
          throw UnimplementedError('The upload url is missing');
        }
        final offset = await _client
            .getCurrentOffset(
              uploadUrl,
              headers: Map.from(headers)
                ..addAll({
                  "Tus-Resumable": tusVersion,
                }),
            )
            .timeout(
              _timeout,
              onTimeout: () => throw TimeoutException("Get current offset timeout"),
            );
        _logger.d(
          "GET CURRENT OFFSET\n=> Offset: $offset",
        );
        final totalBytes = await _file.length();
        await _uploadNextChunk(
          offset: offset,
          uploadUrl: uploadUrl,
          totalBytes: totalBytes,
          headers: headers,
        );
      } on InternalServerErrorException catch (e) {
        _logger.e("$e");
        await serverErrorCallback?.call(_uploadingModel, e.toString());
        return null;
      } on MissingUploadOffsetException catch (e) {
        _logger.e("$e");
        await failureCallback?.call(_uploadingModel, e.toString());
        return;
      } on http.ClientException catch (e) {
        // Lost internet connection
        _logger.e("$e");
        if (failOnLostConnection) {
          await failureCallback?.call(_uploadingModel, e.toString());
        }
        return;
      } on SocketException catch (e) {
        // Lost internet connection
        _logger.e("$e");
        if (failOnLostConnection) {
          await failureCallback?.call(_uploadingModel, e.toString());
        }
        return;
      } catch (e) {
        _logger.e("$e");
        await failureCallback?.call(_uploadingModel, e.toString());
        return;
      }
    }.call());
    await _currentOperation!.value;
  }

  Future<void> _uploadNextChunk({
    required int offset,
    required int totalBytes,
    required String uploadUrl,
    Map<String, String> headers = const {},
  }) async {
    final byteBuilder = await _file.getData(_currentChunkSize, offset: offset);
    final bytesRead = min(_currentChunkSize, byteBuilder.length);
    final nextChunk = byteBuilder.takeBytes();
    _logger.d("UPLOADING NEXT FILE CHUNK\n=> Chunk size: ${nextChunk.length}");
    final startTime = DateTime.now();
    final serverOffset = await _client
        .uploadNextChunkOfFile(
          uploadUrl: uploadUrl,
          nextChunk: nextChunk,
          headers: Map.from(headers)
            ..addAll({
              "Tus-Resumable": tusVersion,
              "Upload-Offset": "$offset",
              "Content-Type": "application/offset+octet-stream"
            }),
        )
        .timeout(
          _timeout,
          onTimeout: () => offset,
        );
    final endTime = DateTime.now();
    final diff = endTime.difference(startTime);
    _logger.d("UPLOADING HAS TAKEN\n=> Time: ${diff.inMilliseconds}");
    final potential = (_currentChunkSize * (_optimalChunkSendTime / diff.inMilliseconds)).toInt();
    _currentChunkSize = max(potential, _minChunkSize);
    final nextOffset = offset + bytesRead;
    if (nextOffset != serverOffset) {
      throw MissingUploadOffsetException(
        message:
            "response contains different Upload-Offset value ($serverOffset) than expected ($offset)",
      );
    }
    await progressCallback?.call(_uploadingModel, nextOffset / totalBytes);
    if (nextOffset >= totalBytes) {
      await completeCallback?.call(_uploadingModel, _uploadUrl.toString());
      return;
    }
    if (uploadingIsPaused) {
      return;
    } else {
      await _uploadNextChunk(
        offset: nextOffset,
        uploadUrl: uploadUrl,
        totalBytes: totalBytes,
        headers: headers,
      );
    }
  }
}
