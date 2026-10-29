import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:dukania/features/purchases/bill_reader/bill_parser.dart';
import 'package:dukania/features/purchases/bill_reader/pdf_words.dart';

void main() {
  test('a real PDF bill is read word by word and parsed', () async {
    final doc = pw.Document();
    pw.Widget cell(String s, {bool right = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        s,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GUPTA TRADERS', style: const pw.TextStyle(fontSize: 18)),
            pw.Text('GSTIN: 27ABCDE1234F1Z5'),
            pw.Text('Invoice No: GT/245     Date: 08-10-2026'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: const {
                0: pw.FixedColumnWidth(30),
                1: pw.FlexColumnWidth(4),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.5),
                5: pw.FlexColumnWidth(1.2),
                6: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  children: [
                    cell('S.No'),
                    cell('Description of Goods'),
                    cell('HSN'),
                    cell('Qty'),
                    cell('Rate'),
                    cell('GST %'),
                    cell('Amount'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    cell('1'),
                    cell('AMUL GHEE 1LTR TIN'),
                    cell('0405'),
                    cell('10', right: true),
                    cell('550.00', right: true),
                    cell('12', right: true),
                    cell('6,160.00', right: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    cell('2'),
                    cell('TATA SALT 1KG'),
                    cell('2501'),
                    cell('50', right: true),
                    cell('24.00', right: true),
                    cell('5', right: true),
                    cell('1,260.00', right: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    cell(''),
                    cell('Grand Total'),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell('7,420.00', right: true),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final words = await readPdfWords(await doc.save());
    expect(
      words.map((w) => w.text),
      containsAll(['GUPTA', 'AMUL', '6,160.00']),
    );
    final bill = parseBill(words);
    expect(bill.billNo, 'GT/245');
    expect(bill.date, DateTime(2026, 10, 8));
    expect(bill.gstins, ['27ABCDE1234F1Z5']);
    expect(bill.supplierName, 'GUPTA TRADERS');
    expect(bill.total, 7420);
    expect(bill.lines.map((l) => l.name), [
      'AMUL GHEE 1LTR TIN',
      'TATA SALT 1KG',
    ]);
    expect(bill.lines.map((l) => l.value), [5500, 1200]);
    expect(bill.lines.every((l) => l.agrees), isTrue);
  });

  test('not a PDF', () async {
    await expectLater(
      readPdfWords(Uint8List.fromList('hello'.codeUnits)),
      throwsA(isA<PdfReadError>()),
    );
  });
}
