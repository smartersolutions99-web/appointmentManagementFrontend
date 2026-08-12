import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web: napravi fajl u memoriji i pokreni preuzimanje u browseru.
///
/// Dodajemo „BOM“ (﻿) na početak da bi Excel ispravno pročitao naša slova
/// (č, ć, š, đ, ž). Vraća `null` jer browser sam bira gdje čuva fajl.
Future<String?> downloadTextFile(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) async {
  final bytes = utf8.encode('﻿$content');
  final blob = html.Blob(<dynamic>[bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return null;
}

/// Web: preuzmi binarni fajl (npr. .xlsx) iz gotovih bajtova. Vraća `null`
/// jer browser sam bira gdje čuva fajl.
Future<String?> downloadBytesFile(String filename, List<int> bytes,
    {String mime =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}) async {
  final blob = html.Blob(<dynamic>[bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return null;
}
