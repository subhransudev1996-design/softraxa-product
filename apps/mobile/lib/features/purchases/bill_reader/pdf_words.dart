import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

import 'bill_parser.dart';

/// Why a PDF couldn't be read.
class PdfReadError implements Exception {
  const PdfReadError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The words of a PDF, each where it sits on its page (points from the
/// top-left). Read with PDFium on the device — no internet, no cost — in a
/// background isolate so the screen doesn't stall.
///
/// A scanned bill (a picture, no text inside) has no words: that's a
/// [PdfReadError] the screen explains.
Future<List<BillWord>> readPdfWords(Uint8List bytes, {int maxPages = 20}) =>
    Isolate.run(() => _read(bytes, maxPages));

List<BillWord> _read(Uint8List bytes, int maxPages) {
  final pdfium = getPdfium();
  pdfium.FPDF_InitLibrary();
  final data = malloc<ffi.Uint8>(bytes.length);
  // The character's full box (its advance width and the font's height),
  // so letters of a word touch and a real gap means a new word.
  final box = malloc<FS_RECTF>();
  try {
    data.asTypedList(bytes.length).setAll(0, bytes);
    final doc = pdfium.FPDF_LoadMemDocument(
      data.cast(),
      bytes.length,
      ffi.nullptr,
    );
    if (doc == ffi.nullptr) {
      final err = pdfium.FPDF_GetLastError();
      throw PdfReadError(
        err ==
                4 // FPDF_ERR_PASSWORD
            ? 'This PDF has a password. Open it, save a copy without the password, and try again.'
            : 'This file could not be opened as a PDF.',
      );
    }
    final words = <BillWord>[];
    try {
      final pages = pdfium.FPDF_GetPageCount(doc);
      for (var p = 0; p < pages && p < maxPages; p++) {
        final page = pdfium.FPDF_LoadPage(doc, p);
        if (page == ffi.nullptr) continue;
        final text = pdfium.FPDFText_LoadPage(page);
        try {
          if (text == ffi.nullptr) continue;
          final height = pdfium.FPDF_GetPageHeightF(page);
          final count = pdfium.FPDFText_CountChars(text);
          final buf = StringBuffer();
          double wl = 0, wt = 0, wr = 0, wb = 0;

          void flush() {
            final s = buf.toString().trim();
            if (s.isNotEmpty) words.add(BillWord(s, wl, wt, wr, wb, page: p));
            buf.clear();
          }

          for (var i = 0; i < count; i++) {
            final code = pdfium.FPDFText_GetUnicode(text, i);
            if (code == 32 ||
                code == 0xA0 ||
                code == 10 ||
                code == 13 ||
                code == 9 ||
                code == 0 ||
                code == 0xFFFE ||
                code == 0xFFFF) {
              flush();
              continue;
            }
            if (pdfium.FPDFText_GetLooseCharBox(text, i, box) == 0) continue;
            // PDF y runs up from the bottom; bills are read top-down.
            final cl = box.ref.left, cr = box.ref.right;
            final ct = height - box.ref.top, cb = height - box.ref.bottom;
            if (buf.isNotEmpty) {
              final wh = wb - wt;
              final mid = (ct + cb) / 2;
              final sameLine = mid >= wt && mid <= wb;
              // A gap as wide as a space, or a jump to another line, starts
              // a new word even without a space character.
              if (!sameLine || cl - wr > wh * 0.2 || cl < wl - wh) flush();
            }
            if (buf.isEmpty) {
              wl = cl;
              wt = ct;
              wr = cr;
              wb = cb;
            } else {
              if (cl < wl) wl = cl;
              if (ct < wt) wt = ct;
              if (cr > wr) wr = cr;
              if (cb > wb) wb = cb;
            }
            buf.writeCharCode(code);
          }
          flush();
        } finally {
          if (text != ffi.nullptr) pdfium.FPDFText_ClosePage(text);
          pdfium.FPDF_ClosePage(page);
        }
      }
    } finally {
      pdfium.FPDF_CloseDocument(doc);
    }
    if (words.isEmpty) {
      throw const PdfReadError(
        'This PDF has no text inside — it is a scanned picture of the bill. '
        'Ask the supplier for the PDF from their billing software, or an Excel file.',
      );
    }
    return words;
  } finally {
    malloc.free(data);
    malloc.free(box);
  }
}
