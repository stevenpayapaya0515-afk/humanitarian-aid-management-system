import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildReportPdf({
  required Map<String, dynamic> totals,
  required List<Map<String, dynamic>> barangays,
  required String scope,
  required String analysis,
  required List<(String, String)> columns,
}) async {
  final document = pw.Document();
  final green = PdfColor.fromInt(0xff185c37);

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 15, color: green)),
  );

  pw.Widget breakdown(String title, List<(String, String)> fields) {
    return pw.TableHelper.fromTextArray(
      headers: [title, for (final field in fields) field.$1],
      data: [
        for (final row in barangays)
          [row['barangay'] ?? '', for (final field in fields) row[field.$2] ?? 0],
      ],
      headerDecoration: pw.BoxDecoration(color: green),
      headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    header: (_) => pw.Text('AidTrack  |  Household vulnerability and aid distribution',
        style: pw.TextStyle(color: green)),
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
    ),
    build: (_) => [
      heading('Household report'),
      pw.Text(scope),
      pw.Text('Date range applies to household registration dates (Philippine time).'),
      heading('Household overview'),
      pw.TableHelper.fromTextArray(
        headers: [for (final field in columns.skip(1).take(4)) field.$1],
        data: [[for (final field in columns.skip(1).take(4)) totals[field.$2] ?? 0]],
      ),
      heading('Assessment coverage'),
      pw.Text(analysis),
      heading('Aid distribution'),
      pw.Text('Actual deliveries: ${totals['aid_distributions'] ?? 0}     '
          'Practice entries: ${totals['simulated_distributions'] ?? 0}'),
      heading('Barangay breakdown'),
      if (barangays.isEmpty) pw.Text('No households match these filters.'),
      if (barangays.isNotEmpty) ...[
        breakdown('Barangay', columns.sublist(1, 8)),
        pw.SizedBox(height: 12),
        breakdown('Barangay', columns.sublist(8)),
      ],
    ],
  ));
  return document.save();
}
