import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../models/models.dart';
import '../../shared/format.dart';
import 'reports_provider.dart';

// ------------------------------- Boje i stilovi -------------------------------
// ARGB hex (alpha prvi). Brend salona je ljubičasta (#6750A4).
final ExcelColor _brand = ExcelColor.fromHexString('FF6750A4'); // zaglavlja sekcija
final ExcelColor _brandSoft = ExcelColor.fromHexString('FFEADDFF'); // nazivi kolona
final ExcelColor _totalSoft = ExcelColor.fromHexString('FFF3EFFA'); // redovi „UKUPNO"

final CellStyle _titleStyle = CellStyle(
  bold: true,
  fontSize: 15,
  fontColorHex: ExcelColor.white,
  backgroundColorHex: _brand,
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
);
final CellStyle _subtitleStyle = CellStyle(
  bold: true,
  fontSize: 11,
  horizontalAlign: HorizontalAlign.Center,
);
final CellStyle _sectionStyle = CellStyle(
  bold: true,
  fontSize: 12,
  fontColorHex: ExcelColor.white,
  backgroundColorHex: _brand,
  horizontalAlign: HorizontalAlign.Left,
);
final CellStyle _colHeadStyle = CellStyle(
  bold: true,
  backgroundColorHex: _brandSoft,
  horizontalAlign: HorizontalAlign.Center,
);
final CellStyle _bold = CellStyle(bold: true);
final CellStyle _totalRow = CellStyle(bold: true, backgroundColorHex: _totalSoft);

// ------------------------------ Ćelije / redovi ------------------------------

CellValue _t(String s) => TextCellValue(s);
CellValue _i(int n) => IntCellValue(n);

/// Novčana ćelija kao broj zaokružen na 2 decimale (da Excel može da računa).
CellValue _money(double v) => DoubleCellValue((v * 100).round() / 100);

/// Procenat: broj (npr. 50) ili „—" kad nije podešen.
CellValue _pct(double? v) => v == null ? _t('—') : DoubleCellValue(v);

/// Upiši jednu ćeliju (vrijednost + opciono stil).
void _put(Sheet sh, int row, int col, CellValue value, [CellStyle? style]) {
  final cell =
      sh.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
  cell.value = value;
  if (style != null) cell.cellStyle = style;
}

/// Obojena traka preko cijele širine (naslov/sekcija) — spojene ćelije.
void _bar(Sheet sh, int row, String text, int lastCol, CellStyle style) {
  for (var c = 0; c <= lastCol; c++) {
    _put(sh, row, c, c == 0 ? _t(text) : _t(''), style);
  }
  sh.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row),
  );
}

/// Red naziva kolona (bold + blaga podloga).
void _colHeaders(Sheet sh, int row, List<String> headers) {
  for (var c = 0; c < headers.length; c++) {
    _put(sh, row, c, _t(headers[c]), _colHeadStyle);
  }
}

// ============================ ZBIRNI IZVJEŠTAJ ============================

/// Pravi .xlsx sa JEDNIM, sređenim sheetom: naslov + „Ukupno" + „Po uslugama"
/// + „Po zaposlenima" (svaka sekcija ima obojeno zaglavlje i bold nazive kolona).
List<int> buildSummaryWorkbook(DetailedReport report, DateTimeRange range) {
  final excel = Excel.createExcel();
  final sh = excel['Izvještaj'];
  const lastCol = 8; // najšira sekcija (po zaposlenima) ima 9 kolona (0..8)
  final period = '${Format.date(range.start)} – ${Format.date(range.end)}';

  // Širine kolona (da ne izgleda prazno/stisnuto).
  const widths = <double>[26, 14, 12, 12, 12, 16, 15, 15, 22];
  for (var c = 0; c < widths.length; c++) {
    sh.setColumnWidth(c, widths[c]);
  }

  var r = 0;

  // ---- Naslov + period ----
  _bar(sh, r++, 'IZVJEŠTAJ SALONA', lastCol, _titleStyle);
  _bar(sh, r++, 'Period: $period', lastCol, _subtitleStyle);
  r++; // prazan red

  // ---- Sekcija: UKUPNO (salon) ----
  _bar(sh, r++, 'UKUPNO (SALON)', lastCol, _sectionStyle);
  _colHeaders(sh, r++, const [
    'Period',
    'Zakazani',
    'Završeni',
    'Otkazani',
    'Nije se pojavio',
    'Ukupno termina',
    'Prihod',
    'Profit',
  ]);
  final profit = report.barbers.fold<double>(0, (s, b) => s + b.salonKeep);
  final o = report.overall;
  // Cijeli zbirni red je podebljan — to je najbitniji red izvještaja.
  _put(sh, r, 0, _t(period), _totalRow);
  _put(sh, r, 1, _i(o.scheduled), _totalRow);
  _put(sh, r, 2, _i(o.completed), _totalRow);
  _put(sh, r, 3, _i(o.cancelled), _totalRow);
  _put(sh, r, 4, _i(o.noShow), _totalRow);
  _put(sh, r, 5, _i(o.total), _totalRow);
  _put(sh, r, 6, _money(report.totalRevenue), _totalRow);
  _put(sh, r, 7, _money(profit), _totalRow);
  r += 2; // red + prazan

  // ---- Sekcija: PO USLUGAMA ----
  _bar(sh, r++, 'PO USLUGAMA', lastCol, _sectionStyle);
  _colHeaders(sh, r++, const [
    'Usluga',
    'Cijena usluge',
    'Broj odrađenih',
    'Suma',
  ]);
  var svcCount = 0;
  var svcSum = 0.0;
  for (final s in report.services) {
    _put(sh, r, 0, _t(s.name));
    _put(sh, r, 1, s.unitPrice == null ? _t('—') : _money(s.unitPrice!));
    _put(sh, r, 2, _i(s.completedCount));
    _put(sh, r, 3, _money(s.revenue), _bold);
    svcCount += s.completedCount;
    svcSum += s.revenue;
    r++;
  }
  _put(sh, r, 0, _t('UKUPNO'), _totalRow);
  _put(sh, r, 1, _t(''), _totalRow);
  _put(sh, r, 2, _i(svcCount), _totalRow);
  _put(sh, r, 3, _money(svcSum), _totalRow);
  r += 2;

  // ---- Sekcija: PO ZAPOSLENIMA ----
  _bar(sh, r++, 'PO ZAPOSLENIMA', lastCol, _sectionStyle);
  _colHeaders(sh, r++, const [
    'Zaposleni',
    'Procenat (%)',
    'Zakazani',
    'Završeni',
    'Otkazani',
    'Nije se pojavio',
    'Ukupno termina',
    'Prihod',
    'Profit (dio zaposlenog)',
  ]);
  var sSch = 0, sCom = 0, sCan = 0, sNo = 0, sTot = 0;
  var sRev = 0.0, sCut = 0.0;
  for (final b in report.barbers) {
    _put(sh, r, 0, _t(b.name));
    _put(sh, r, 1, _pct(b.commission));
    _put(sh, r, 2, _i(b.counts.scheduled));
    _put(sh, r, 3, _i(b.counts.completed));
    _put(sh, r, 4, _i(b.counts.cancelled));
    _put(sh, r, 5, _i(b.counts.noShow));
    _put(sh, r, 6, _i(b.counts.total));
    _put(sh, r, 7, _money(b.revenue), _bold);
    _put(sh, r, 8, _money(b.employeeCut), _bold);
    sSch += b.counts.scheduled;
    sCom += b.counts.completed;
    sCan += b.counts.cancelled;
    sNo += b.counts.noShow;
    sTot += b.counts.total;
    sRev += b.revenue;
    sCut += b.employeeCut;
    r++;
  }
  _put(sh, r, 0, _t('UKUPNO'), _totalRow);
  _put(sh, r, 1, _t(''), _totalRow);
  _put(sh, r, 2, _i(sSch), _totalRow);
  _put(sh, r, 3, _i(sCom), _totalRow);
  _put(sh, r, 4, _i(sCan), _totalRow);
  _put(sh, r, 5, _i(sNo), _totalRow);
  _put(sh, r, 6, _i(sTot), _totalRow);
  _put(sh, r, 7, _money(sRev), _totalRow);
  _put(sh, r, 8, _money(sCut), _totalRow);

  excel.delete('Sheet1');
  return excel.save() ?? <int>[];
}

// =========================== DETALJNI IZVJEŠTAJ ===========================

/// Jedan red detaljnog izvještaja — svi podaci o jednom terminu.
class DetailedApptRow {
  final int? employeeId; // za grupisanje po barberu
  final DateTime? start;
  final DateTime? end;
  final String barber;
  final String customer;
  final String phone;
  final String service;
  final double price;
  final int? duration;
  final AppointmentStatus? status; // enum — da ćeliju možemo obojiti po statusu
  final String note;

  const DetailedApptRow({
    required this.employeeId,
    required this.start,
    required this.end,
    required this.barber,
    required this.customer,
    required this.phone,
    required this.service,
    required this.price,
    required this.duration,
    required this.status,
    required this.note,
  });
}

/// Boja ćelije statusa: zakazan = neutralno sivo, otkazan = žuto (upozorenje),
/// nije se pojavio = jako crveno (opasnost), završen = sretno zeleno.
CellStyle _statusStyle(AppointmentStatus? s) {
  switch (s) {
    case AppointmentStatus.completed:
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('FF43A047'), // zelena
        horizontalAlign: HorizontalAlign.Center,
      );
    case AppointmentStatus.cancelled:
      return CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFFFCA28'), // žuta/amber
        horizontalAlign: HorizontalAlign.Center,
      );
    case AppointmentStatus.noShow:
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('FFE53935'), // crvena
        horizontalAlign: HorizontalAlign.Center,
      );
    case AppointmentStatus.scheduled:
    default:
      return CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('FFE0E0E0'), // sivo
        horizontalAlign: HorizontalAlign.Center,
      );
  }
}

/// Paleta boja za grupe barbera (svaki barber dobija svoju svijetlu boju).
/// `header` je jača nijansa (traka sa imenom), `row` je svijetla (redovi).
final List<({ExcelColor header, ExcelColor row})> _barberPalette = [
  (header: ExcelColor.fromHexString('FFA5D6A7'), row: ExcelColor.fromHexString('FFE8F5E9')), // zelena
  (header: ExcelColor.fromHexString('FFFFF176'), row: ExcelColor.fromHexString('FFFFFDE7')), // žuta
  (header: ExcelColor.fromHexString('FF90CAF9'), row: ExcelColor.fromHexString('FFE3F2FD')), // plava
  (header: ExcelColor.fromHexString('FFFFB74D'), row: ExcelColor.fromHexString('FFFFF3E0')), // narandžasta
  (header: ExcelColor.fromHexString('FFCE93D8'), row: ExcelColor.fromHexString('FFF3E5F5')), // ljubičasta
  (header: ExcelColor.fromHexString('FFF48FB1'), row: ExcelColor.fromHexString('FFFCE4EC')), // roze
  (header: ExcelColor.fromHexString('FF80CBC4'), row: ExcelColor.fromHexString('FFE0F2F1')), // tirkizna
  (header: ExcelColor.fromHexString('FFEF9A9A'), row: ExcelColor.fromHexString('FFFFEBEE')), // crvena
];

/// Pravi .xlsx sa jednim sheetom „Termini", GRUPISAN po barberu: prvo svi termini
/// jednog barbera (ispod obojene trake sa imenom), pa drugog itd. Svaki barber
/// ima svoju svijetlu boju redova. Zaglavlje i nazivi kolona su obojeni/bold.
List<int> buildDetailedWorkbook(List<DetailedApptRow> rows,
    {DateTimeRange? range}) {
  final excel = Excel.createExcel();
  final sh = excel['Termini'];
  const lastCol = 10; // 11 kolona (0..10)

  const widths = <double>[12, 8, 8, 20, 22, 16, 20, 12, 14, 16, 26];
  for (var c = 0; c < widths.length; c++) {
    sh.setColumnWidth(c, widths[c]);
  }

  var r = 0;
  _bar(sh, r++, 'DETALJNI IZVJEŠTAJ — TERMINI', lastCol, _titleStyle);
  if (range != null) {
    _bar(
      sh,
      r++,
      'Period: ${Format.date(range.start)} – ${Format.date(range.end)}',
      lastCol,
      _subtitleStyle,
    );
  }
  r++; // prazan red

  _colHeaders(sh, r++, const [
    'Datum',
    'Od',
    'Do',
    'Zaposleni',
    'Klijent',
    'Telefon',
    'Usluga',
    'Cijena',
    'Trajanje (min)',
    'Status',
    'Napomena',
  ]);

  // Grupiši po zaposlenom; sekcije poređaj po imenu barbera.
  final groups = <int?, List<DetailedApptRow>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.employeeId, () => <DetailedApptRow>[]).add(row);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) => groups[a]!
        .first
        .barber
        .toLowerCase()
        .compareTo(groups[b]!.first.barber.toLowerCase()));

  final epoch = DateTime(1900);
  var idx = 0;
  for (final key in keys) {
    final list = groups[key]!
      ..sort((a, b) => (a.start ?? epoch).compareTo(b.start ?? epoch));
    final pal = _barberPalette[idx % _barberPalette.length];
    idx++;

    // Traka sa imenom barbera (u jačoj nijansi njegove boje).
    final headStyle = CellStyle(
      bold: true,
      backgroundColorHex: pal.header,
      horizontalAlign: HorizontalAlign.Left,
    );
    _bar(
      sh,
      r++,
      '${list.first.barber}  —  ${list.length} ${list.length == 1 ? 'termin' : 'termina'}',
      lastCol,
      headStyle,
    );

    // Redovi barbera (u svijetloj nijansi njegove boje).
    final rowStyle = CellStyle(backgroundColorHex: pal.row);
    for (final row in list) {
      _put(sh, r, 0, _t(row.start != null ? Format.date(row.start!) : ''),
          rowStyle);
      _put(sh, r, 1, _t(row.start != null ? Format.time(row.start!) : ''),
          rowStyle);
      _put(sh, r, 2, _t(row.end != null ? Format.time(row.end!) : ''), rowStyle);
      _put(sh, r, 3, _t(row.barber), rowStyle);
      _put(sh, r, 4, _t(row.customer), rowStyle);
      _put(sh, r, 5, _t(row.phone), rowStyle);
      _put(sh, r, 6, _t(row.service), rowStyle);
      _put(sh, r, 7, _money(row.price), rowStyle);
      _put(sh, r, 8, row.duration == null ? _t('') : _i(row.duration!),
          rowStyle);
      // Status ćelija ima svoju boju (po statusu), a ne boju barbera.
      _put(sh, r, 9, _t(row.status?.label ?? ''), _statusStyle(row.status));
      _put(sh, r, 10, _t(row.note), rowStyle);
      r++;
    }
  }

  excel.delete('Sheet1');
  return excel.save() ?? <int>[];
}
