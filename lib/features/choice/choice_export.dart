import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/native_bridge.dart';
import 'choice_repository.dart';

enum ChoiceExportFormat {
  pdf('pdf', 'application/pdf', 'PDF'),
  csv('csv', 'text/csv', 'CSV');

  const ChoiceExportFormat(this.extension, this.mimeType, this.label);

  final String extension;
  final String mimeType;
  final String label;
}

/// The native ChoiceListExporter: builds the file and saves it to
/// Downloads/CollegeBook. Returns the saved file's uri.
Future<String> exportChoiceList(
  ChoiceList list,
  ChoiceExportFormat format,
) async {
  final bytes = format == ChoiceExportFormat.pdf
      ? await _pdf(list)
      : _csv(list);
  return saveDownload(
    fileName: _fileName(list.name, format),
    mimeType: format.mimeType,
    bytes: bytes,
  );
}

String _fileName(String? listName, ChoiceExportFormat format) {
  var base = (listName ?? '')
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  if (base.isEmpty) base = 'Choice_list';
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  return '${base}_$stamp.${format.extension}';
}

// ---- CSV ----

Uint8List _csv(ChoiceList list) {
  final sb = StringBuffer('﻿'); // BOM so Excel reads the file as UTF-8
  void row(List<String?> cells) {
    sb.write(
      cells
          .map((c) {
            final v = c ?? '';
            return v.contains(',') || v.contains('"') || v.contains('\n')
                ? '"${v.replaceAll('"', '""')}"'
                : v;
          })
          .join(','),
    );
    sb.write('\r\n');
  }

  row([
    '#',
    'Institute',
    'State',
    'Course',
    'Quota',
    'Category',
    'Fee',
    'Year',
  ]);
  var i = 1;
  for (final c in list.choices) {
    row([
      '${i++}',
      c.institute,
      c.state,
      c.course,
      c.quota,
      c.category,
      c.fee,
      c.year,
    ]);
  }
  return Uint8List.fromList(utf8.encode(sb.toString()));
}

// ---- PDF (A4, 36pt margins, the native column widths and colours) ----

const _green = PdfColor.fromInt(0xFF003300);
const _text = PdfColor.fromInt(0xFF12151B);
const _mutedText = PdfColor.fromInt(0xFF6B7280);
const _border = PdfColor.fromInt(0xFFE5E7EB);
const _zebra = PdfColor.fromInt(0xFFF6F8F7);
const _colW = [24.0, 170.0, 108.0, 82.0, 54.0, 52.0, 33.0];
const _header = [
  '#',
  'Institute',
  'Course',
  'Quota',
  'Category',
  'Fee',
  'Year',
];

Future<Uint8List> _pdf(ChoiceList list) async {
  final count = list.choices.length;
  final date = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
  // Inter (the app font) has the ₹ sign the built-in PDF fonts lack.
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter_regular.ttf'),
      ),
      bold: pw.Font.ttf(await rootBundle.load('assets/fonts/inter_bold.ttf')),
    ),
  );
  pw.Widget cell(String? text, {double size = 8.5, PdfColor color = _text}) =>
      pw.Text(
        text ?? '',
        style: pw.TextStyle(fontSize: size, color: color),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 36,
        marginRight: 36,
        marginTop: 36,
        marginBottom: 36,
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          cell('CollegeBook', size: 9.5, color: _mutedText),
          cell('Page ${context.pageNumber}', size: 9.5, color: _mutedText),
        ],
      ),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (context.pageNumber == 1)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 18),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 4, height: 40, color: _green),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          list.name ?? '',
                          maxLines: 1,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: _text,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        cell(
                          '$count ${count == 1 ? 'choice' : 'choices'}  ·  in order of preference  ·  Exported from CollegeBook on $date',
                          size: 9.5,
                          color: _mutedText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          pw.Container(
            height: 24,
            decoration: const pw.BoxDecoration(
              color: _green,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                for (var i = 0; i < _header.length; i++)
                  pw.Container(
                    width: _colW[i],
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      _header[i],
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      build: (context) => [
        if (count == 0)
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: cell('No choices in this list yet.'),
          ),
        for (var i = 0; i < count; i++)
          pw.Container(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _zebra : null,
              border: const pw.Border(
                bottom: pw.BorderSide(color: _border, width: 0.7),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final (w, child) in [
                  (_colW[0], cell('${i + 1}')),
                  (
                    _colW[1],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        cell(list.choices[i].institute),
                        if ((list.choices[i].state ?? '').isNotEmpty)
                          cell(
                            list.choices[i].state,
                            size: 7.5,
                            color: _mutedText,
                          ),
                      ],
                    ),
                  ),
                  (_colW[2], cell(list.choices[i].course)),
                  (_colW[3], cell(list.choices[i].quota)),
                  (_colW[4], cell(list.choices[i].category)),
                  (
                    _colW[5],
                    cell(
                      (list.choices[i].fee ?? '').isEmpty
                          ? ''
                          : '₹${list.choices[i].fee}',
                    ),
                  ),
                  (_colW[6], cell(list.choices[i].year)),
                ])
                  pw.Container(
                    width: w,
                    padding: const pw.EdgeInsets.all(6),
                    child: child,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
