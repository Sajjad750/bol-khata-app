import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies a picked image into app documents so it survives temp cleanup.
Future<String> persistCustomerPhoto(String sourcePath) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'customer_photos'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final ext = p.extension(sourcePath);
  final filename =
      'c_${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';
  final dest = p.join(dir.path, filename);
  await File(sourcePath).copy(dest);
  return dest;
}
