// Preuzimanje (download) tekstualnog fajla — npr. CSV za Excel.
//
// Koristimo uslovni import: na web-u se učitava prava implementacija
// (preko `dart:html`), a na ostalim platformama „stub“ koji javi grešku.
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
