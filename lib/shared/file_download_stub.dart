import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Desktop / mobilne platforme: upiši fajl u folder „Downloads“ (ako postoji)
/// ili u folder dokumenata aplikacije. Vraća punu putanju sačuvanog fajla.
///
/// Dodajemo „BOM“ (﻿) da bi Excel ispravno pročitao naša slova (č, ć, š, đ, ž).
Future<String?> downloadTextFile(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();

  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(utf8.encode('﻿$content'));
  return file.path;
}
