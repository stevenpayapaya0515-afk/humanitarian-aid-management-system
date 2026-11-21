import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildReportPdf({
  required Map<String, dynamic> totals,
  required List<Map<String, dynamic>> barangays,
  required String scope,
  required String analysis,
  required List<(String, String)> columns,
}) async {
  final logoData = await rootBundle.load('assets/images/aidtrack_symbol.png');
  final reportLogo = pw.MemoryImage(
    logoData.buffer.asUint8List(logoData.offsetInBytes, logoData.lengthInBytes),
  );
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
    header: (context) {
      if (context.pageNumber > 1) {
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'AidTrack | Household Vulnerability and Aid Distribution Report',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, color: green),
          ),
        );
      }

      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(reportLogo, width: 26, height: 26, fit: pw.BoxFit.contain),
                pw.SizedBox(width: 7),
                pw.Text(
                  'AidTrack',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: green,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'Household Vulnerability and Aid Distribution Report',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: green,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              scope,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Date range applies to household registration dates (Philippine time).',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            pw.Container(height: 1, width: double.infinity, color: green),
          ],
        ),
      );
    },
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
    ),
    build: (_) => [
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
