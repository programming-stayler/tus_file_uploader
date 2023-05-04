import 'dart:io';
import 'dart:math';
import 'package:async/async.dart';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:http/http.dart' as http;

import 'utils.dart';
import 'exceptions.dart';
import 'extensions.dart';

class TusFileUploader {
  static const _defaultChunkSize = 128 * 1024; // 128 KB
  final _client = http.Client();

  Uri? _uploadUrl;
  String? customScheme;
  CancelableOperation? _currentOperation;

  late XFile _file;
  late Duration _timeout;
  late int _currentChunkSize;
  late int _optimalChunkSendTime;

  final UploadingProgressCallback? progressCallback;
  final UploadingCompleteCallback? completeCallback;
  final UploadingFailedCallback? failureCallback;
  final Map<String, String> headers;
  final bool failOnLostConnection;
  final Uri baseUrl;

  bool uploadingIsPaused = false;

  TusFileUploader._({
    required String path,
    required this.baseUrl,
    required this.headers,
    required this.failOnLostConnection,
    this.progressCallback,
    this.completeCallback,
    this.failureCallback,
    int? optimalChunkSendTime,
    Uri? uploadUrl,
    int? timeout,
  }) {
    _file = XFile(path);
    _uploadUrl = uploadUrl;
    _currentChunkSize = _defaultChunkSize;
    _timeout = Duration(seconds: timeout ?? 3); // 3 SEC
    _optimalChunkSendTime = optimalChunkSendTime ?? 1000; // 1 SEC
  }

  factory TusFileUploader.init({
    required String path,
    required Uri baseUrl,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    Map<String, String>? headers,
    bool? failOnLostConnection,
    int? optimalChunkSendTime,
    int? timeout,
  }) =>
      TusFileUploader._(
        path: path,
        baseUrl: baseUrl,
        progressCallback: progressCallback,
        completeCallback: completeCallback,
        failureCallback: failureCallback,
        headers: headers ?? const {},
        failOnLostConnection: failOnLostConnection ?? false,
        optimalChunkSendTime: optimalChunkSendTime,
        timeout: timeout,
      );

  factory TusFileUploader.initAndSetup({
    required String path,
    required Uri baseUrl,
    required Uri uploadUrl,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    Map<String, String>? headers,
    bool? failOnLostConnection,
    int? optimalChunkSendTime,
    int? timeout,
  }) =>
      TusFileUploader._(
        path: path,
        baseUrl: baseUrl,
        progressCallback: progressCallback,
        completeCallback: completeCallback,
        failureCallback: failureCallback,
        headers: headers ?? const {},
        failOnLostConnection: failOnLostConnection ?? false,
        optimalChunkSendTime: optimalChunkSendTime,
        uploadUrl: uploadUrl,
        timeout: timeout,
      );

  Future<String?> setupUploadUrl() async {
    if (_uploadUrl != null) {
      return _uploadUrl!.toString();
    }
    try {
      _currentOperation = CancelableOperation.fromFuture(
        _client
            .setupUploadUrl(
              baseUrl: baseUrl,
              headers: headers,
            )
            .timeout(
              _timeout,
              onTimeout: () => baseUrl,
            ),
      );
      _uploadUrl = await _currentOperation!.value;
      return _uploadUrl.toString();
    } catch (e) {
      await failureCallback?.call(_file.path, e.toString());
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
        final resultUrl = _uploadUrl;
        if (resultUrl == null) {
          throw UnimplementedError('The upload url is missing');
        }
        final offset = await _client
            .getCurrentOffset(
              resultUrl,
              headers: Map.from(headers)
                ..addAll({
                  "Tus-Resumable": tusVersion,
                }),
            )
            .timeout(
              _timeout,
              onTimeout: () => 0,
            );
        final totalBytes = await _file.length();
        await _uploadNextChunk(
          offset: offset,
          totalBytes: totalBytes,
          headers: headers,
        );
      } on MissingUploadOffsetException catch (_) {
        final uploadUrl = await setupUploadUrl();
        if (uploadUrl != null) {
          await upload(headers: headers);
        }
        return;
      } on http.ClientException catch (_) {
        // Lost internet connection
        if (failOnLostConnection) {
          await failureCallback?.call(_file.path, e.toString());
        }
        return;
      } on SocketException catch (e) {
        // Lost internet connection
        if (failOnLostConnection) {
          await failureCallback?.call(_file.path, e.toString());
        }
        return;
      } catch (e) {
        await failureCallback?.call(_file.path, e.toString());
        return;
      }
    }.call());
    await _currentOperation!.value;
  }

  Future<void> _uploadNextChunk({
    required int offset,
    required int totalBytes,
    Map<String, String> headers = const {},
  }) async {
    final resultUrl = _uploadUrl;
    if (resultUrl == null) {
      throw UnimplementedError('The upload url is missing');
    }
    final byteBuilder = await _file.getData(_currentChunkSize, offset: offset);
    final bytesRead = min(_currentChunkSize, byteBuilder.length);
    final nextChunk = byteBuilder.takeBytes();
    final startTime = DateTime.now();
    final serverOffset = await _client
        .uploadNextChunkOfFile(
          uploadUrl: resultUrl,
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
    _currentChunkSize = (_currentChunkSize * (_optimalChunkSendTime / diff.inMilliseconds)).toInt();
    final nextOffset = offset + bytesRead;
    if (nextOffset != serverOffset) {
      throw MissingUploadOffsetException(
        message:
            "response contains different Upload-Offset value ($serverOffset) than expected ($offset)",
      );
    }
    await progressCallback?.call(_file.path, nextOffset / totalBytes);
    if (nextOffset >= totalBytes) {
      await completeCallback?.call(_file.path, _uploadUrl.toString());
      return;
    }
    if (uploadingIsPaused) {
      return;
    } else {
      await _uploadNextChunk(
        offset: nextOffset,
        totalBytes: totalBytes,
      );
    }
  }
}
