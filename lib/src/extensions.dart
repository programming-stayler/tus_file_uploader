import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data' show BytesBuilder;
import 'dart:typed_data' show Uint8List;

import 'package:cross_file/cross_file.dart' show XFile;
import "package:path/path.dart" as p;

import 'exceptions.dart';

extension HttpUtils on http.Client {
  Future<Uri> setupUploadUrl({
    required Uri baseUrl,
    Map<String, String> headers = const {},
  }) async {
    final response = await post(baseUrl, headers: headers);
    if (!(response.statusCode >= 200 && response.statusCode < 300) && response.statusCode != 404) {
      throw ProtocolException(response.statusCode);
    }
    final urlStr = response.headers["location"] ?? "";
    if (urlStr.isEmpty) {
      throw MissingUploadUriException();
    }
    return baseUrl.parseUrl(urlStr);
  }

  Future<int> getCurrentOffset(
    Uri uploadUrl, {
    Map<String, String>? headers,
  }) async {
    final offsetHeaders = Map<String, String>.from(headers ?? {});
    final response = await head(
      uploadUrl,
      headers: offsetHeaders,
    );
    if (response.statusCode == 401) {
      throw UnauthorizedException(message: response.body);
    }
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(response.statusCode);
    }
    final serverOffset = response.headers["upload-offset"]?.parseOffset();
    if (serverOffset == null) {
      throw MissingUploadOffsetException();
    }
    return serverOffset;
  }

  Future<int> uploadNextChunkOfFile({
    required Uri uploadUrl,
    required Uint8List nextChunk,
    Map<String, String> headers = const {},
  }) async {
    final response = await patch(
      uploadUrl,
      body: nextChunk,
      headers: headers,
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(response.statusCode);
    }
    final serverOffset = response.headers["upload-offset"]?.parseOffset();
    if (serverOffset == null) {
      throw ChunkUploadFailedException();
    }
    return serverOffset;
  }
}

extension XFileUtils on XFile {
  Future<BytesBuilder> getData(int maxChunkSize, {int? offset}) async {
    final start = offset ?? 0;
    int end = start + maxChunkSize;
    final fileSize = await length();
    end = end > fileSize ? fileSize : end;

    final result = BytesBuilder();
    await for (final chunk in openRead(start, end)) {
      result.add(chunk);
    }
    return result;
  }

  String generateMetadata({Map<String, String>? originalMetadata}) {
    final meta = Map<String, String>.from(originalMetadata ?? {});

    if (!meta.containsKey("filename")) {
      meta["filename"] = p.basename(path);
    }

    return meta.entries
        .map((entry) => "${entry.key} ${base64.encode(utf8.encode(entry.value))}")
        .join(",");
  }

  String? generateFingerprint() {
    return path.replaceAll(RegExp(r"\W+"), '.');
  }
}

extension UriTus on Uri {
  Uri parseUrl(String urlStr) {
    String resultUrlStr = urlStr;
    if (urlStr.contains(",")) {
      resultUrlStr = urlStr.substring(0, urlStr.indexOf(","));
    }
    Uri uploadUrl = Uri.parse(resultUrlStr);
    if (uploadUrl.host.isEmpty) {
      uploadUrl = uploadUrl.replace(host: host, port: port);
    }
    if (uploadUrl.scheme.isEmpty) {
      uploadUrl = uploadUrl.replace(scheme: scheme);
    }
    return uploadUrl;
  }
}

extension StringTus on String {
  int? parseOffset() {
    if (isEmpty) {
      return null;
    }
    String offset = this;
    if (offset.contains(",")) {
      offset = offset.substring(0, offset.indexOf(","));
    }
    return int.tryParse(offset);
  }
}
