import 'package:flutter/material.dart';

import 'package:example/src/app.dart';
import 'package:logger/logger.dart';

void main() {
  final logger = Logger(level: Level.all);
  logger.d("Get current offset\n=> Offset: 10");
  runApp(const App());
}
