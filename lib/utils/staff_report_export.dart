import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Staff report prepared for a Word or PDF download.
class StaffReportDocument {
  const StaffReportDocument({
    required this.staffName,
    required this.body,
    this.rangeLabel,
  });

  final String staffName;
  final String? rangeLabel;
  final String body;

  static const title = 'Project Tracker Staff Performance Report';
}

Future<Uint8List> staffReportPdf(StaffReportDocument document) async {
  final doc = pw.Document();
  final paragraphs = _reportLines(document.body);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 56),
      build: (context) => [
        pw.Text(
          StaffReportDocument.title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        if (document.rangeLabel != null && document.rangeLabel!.trim().isNotEmpty) ...[
          pw.Text(
            document.rangeLabel!.trim(),
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Text(document.staffName, style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 16),
        for (final line in paragraphs)
          if (line.isEmpty)
            pw.SizedBox(height: 10)
          else
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
              ),
            ),
      ],
    ),
  );
  return doc.save();
}

Uint8List staffReportDocx(StaffReportDocument document) {
  final range = document.rangeLabel?.trim();
  final paragraphs = StringBuffer()
    ..write(
      _docxParagraph(StaffReportDocument.title, bold: true, sizeHalfPoints: 36),
    );
  if (range != null && range.isNotEmpty) {
    paragraphs.write(_docxParagraph(range, sizeHalfPoints: 24));
  }
  paragraphs
    ..write(_docxParagraph(document.staffName, sizeHalfPoints: 24))
    ..write(_docxParagraph(''));
  for (final line in _reportLines(document.body)) {
    paragraphs.write(_docxParagraph(line));
  }
  final documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        '_rels/.rels',
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''',
      ),
    )
    ..addFile(ArchiveFile.string('word/document.xml', documentXml));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

List<String> _reportLines(String body) {
  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return [for (final line in lines) line.trimRight()];
}

String _docxParagraph(
  String text, {
  bool bold = false,
  int sizeHalfPoints = 22,
  String? color,
}) {
  final runProps = StringBuffer('<w:rPr>');
  if (bold) runProps.write('<w:b/>');
  if (color != null) runProps.write('<w:color w:val="$color"/>');
  runProps.write('<w:sz w:val="$sizeHalfPoints"/>');
  runProps.write('<w:szCs w:val="$sizeHalfPoints"/>');
  runProps.write('</w:rPr>');
  return '''
<w:p>
  <w:pPr><w:spacing w:after="120"/></w:pPr>
  <w:r>
    $runProps
    <w:t xml:space="preserve">${_xmlText(text)}</w:t>
  </w:r>
</w:p>
''';
}

String _xmlText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final allowed = rune == 0x9 ||
        rune == 0xA ||
        rune == 0xD ||
        (rune >= 0x20 && rune <= 0xD7FF) ||
        (rune >= 0xE000 && rune <= 0xFFFD);
    if (allowed) {
      buffer.write(switch (rune) {
        0x26 => '&amp;',
        0x3C => '&lt;',
        0x3E => '&gt;',
        _ => String.fromCharCode(rune),
      });
    }
  }
  return buffer.toString();
}
