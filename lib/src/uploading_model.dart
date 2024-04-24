import 'dart:io';

import 'package:flutter/foundation.dart';

class UploadingModel {

  final int id;
  final String path;
  final String? customScheme;
  String? uploadUrl;

  UploadingModel({
    required this.path,
    this.customScheme,
    int? id,
    this.uploadUrl,
  }): id = id ?? UniqueKey().hashCode;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'customScheme': customScheme,
      'uploadUrl': uploadUrl,
    };
  }

  factory UploadingModel.fromJson(Map<String, dynamic> map) {
    return UploadingModel(
      id: map['id'] as int,
      path: map['path'] as String,
      customScheme: map['customScheme'] as String,
      uploadUrl: map['uploadUrl'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (runtimeType != other.runtimeType) return false;

    final otherUploadingModel = other as UploadingModel;
    var equals = id == otherUploadingModel.id;

    return identical(this, other) || equals;
  }

  @override
  int get hashCode => path.hashCode ^ customScheme.hashCode;

  bool get existsSync => File(path).existsSync();

  Future<bool> get exists async => File(path).exists();
}
