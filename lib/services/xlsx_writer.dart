import 'dart:convert';

import 'package:archive/archive.dart';

/// One tab of a workbook.
class Sheet {
  Sheet(this.name, {this.headers = const []});

  /// Excel forbids `[]:*?/\` in a tab name and caps it at 31 characters, so
  /// the caller's label is sanitised rather than producing a file Excel
  /// refuses to open.
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows = [];

  void add(List<Object?> row) => rows.add(row);
}

/// A minimal `.xlsx` writer.
///
/// Hand-rolled because the maintained `excel` package pins `archive ^3`, while
/// `basic_utils` — which generates the host's TLS certificate — requires
/// `archive ^4`. Pinning a security-relevant dependency backwards to
/// accommodate a reporting convenience is the worse trade, and the slice of
/// the format a report needs is small: a zip of XML parts, with values written
/// inline so there is no shared-string table to maintain.
///
/// Produces numbers as numbers (so Excel will sum a balance column) and
/// everything else as text.
class XlsxWriter {
  const XlsxWriter();

  List<int> build(List<Sheet> sheets) {
    if (sheets.isEmpty) throw ArgumentError('A workbook needs a sheet.');
    final archive = Archive();

    void addFile(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addFile('[Content_Types].xml', _contentTypes(sheets.length));
    addFile('_rels/.rels', _rootRels);
    addFile('xl/workbook.xml', _workbook(sheets));
    addFile('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    for (var i = 0; i < sheets.length; i++) {
      addFile('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }

    return ZipEncoder().encode(archive);
  }

  // ---- parts ------------------------------------------------------------

  String _contentTypes(int sheetCount) {
    final sheets = [
      for (var i = 1; i <= sheetCount; i++)
        '<Override PartName="/xl/worksheets/sheet$i.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.worksheet+xml"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats'
        '-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.'
        'openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '$sheets</Types>';
  }

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>';

  String _workbook(List<Sheet> sheets) {
    final entries = [
      for (var i = 0; i < sheets.length; i++)
        '<sheet name="${_escape(_tabName(sheets[i].name))}" '
            'sheetId="${i + 1}" r:id="rId${i + 1}"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
        '2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/'
        '2006/relationships"><sheets>$entries</sheets></workbook>';
  }

  String _workbookRels(int sheetCount) {
    final entries = [
      for (var i = 1; i <= sheetCount; i++)
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
            'officeDocument/2006/relationships/worksheet" '
            'Target="worksheets/sheet$i.xml"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships">$entries</Relationships>';
  }

  String _sheet(Sheet sheet) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main"><sheetData>');

    var rowIndex = 1;
    if (sheet.headers.isNotEmpty) {
      buffer.write(_row(rowIndex++, sheet.headers));
    }
    for (final row in sheet.rows) {
      buffer.write(_row(rowIndex++, row));
    }

    buffer.write('</sheetData></worksheet>');
    return buffer.toString();
  }

  String _row(int index, List<Object?> values) {
    final cells = StringBuffer();
    for (var c = 0; c < values.length; c++) {
      final value = values[c];
      if (value == null) continue;
      final ref = '${_columnName(c)}$index';
      if (value is num && value.isFinite) {
        cells.write('<c r="$ref"><v>$value</v></c>');
      } else {
        // Inline string: no shared-string table to keep consistent.
        cells.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
            '${_escape('$value')}</t></is></c>');
      }
    }
    return '<row r="$index">$cells</row>';
  }

  /// 0 -> A, 25 -> Z, 26 -> AA.
  static String _columnName(int index) {
    var n = index;
    final out = StringBuffer();
    do {
      out.write(String.fromCharCode(65 + (n % 26)));
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return String.fromCharCodes(out.toString().codeUnits.reversed);
  }

  static String _tabName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    final safe = cleaned.isEmpty ? 'Sheet' : cleaned;
    return safe.length <= 31 ? safe : safe.substring(0, 31);
  }

  /// XML escaping, plus stripping the control characters Excel rejects — a
  /// stray one in a member's name would otherwise produce a file that opens
  /// as "unreadable content".
  static String _escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
