import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/formatters.dart';
import '../data/transcript_models.dart';

/// 将转写结果生成为 DOCX（Word OOXML）文件字节。
///
/// 不依赖原生 Office 库：手工组装最小合法的 OOXML 包
/// （`[Content_Types].xml` + `_rels/.rels` + `word/document.xml`）并打成 zip。
class DocxExporter {
  DocxExporter._();

  /// 主题色，与 AppColors.primary 一致（时间戳 / 说话人标签着色）。
  static const _accentHex = 'E5474D';

  /// 正文深灰。
  static const _bodyHex = '333333';

  /// 元信息浅灰。
  static const _mutedHex = '8A8A8A';

  static Uint8List build({
    required String title,
    required List<TranscriptSegment> segments,
    DateTime? createdAt,
    double? durationSec,
  }) {
    final buf = StringBuffer();
    buf.write(_titleParagraph(title));
    final metaParts = <String>[
      if (createdAt != null) formatDateTime(createdAt),
      if (durationSec != null && durationSec > 0)
        '时长 ${formatDuration(durationSec)}',
      '${segments.length} 个段落',
    ];
    if (metaParts.isNotEmpty) {
      buf.write(
        _paragraph(
          runs: [_run(metaParts.join('  ·  '), color: _mutedHex, sz: 18)],
          center: true,
          after: 320,
        ),
      );
    }
    for (final s in segments) {
      final label = s.speaker == null ? '' : '${s.speakerLabel}　';
      buf.write(
        _paragraph(
          runs: [
            // 时间戳后留两个空格，与说话人/正文分隔
            _run(
              '[${formatClock(s.startSec)}]  ',
              color: _accentHex,
              sz: 21,
              bold: true,
            ),
            if (label.isNotEmpty)
              _run(label, color: _accentHex, sz: 21, bold: true),
            _run(s.text, color: _bodyHex, sz: 21),
          ],
          after: 140,
        ),
      );
    }

    final document = _xml('''<w:document
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
${buf.toString()}    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1560" w:bottom="1440" w:left="1560"
          w:header="851" w:footer="992" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>''');

    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..add(ArchiveFile.string('_rels/.rels', _rootRels))
      ..add(ArchiveFile.string('word/document.xml', document));
    return ZipEncoder().encodeBytes(archive);
  }

  // —— OOXML 组装 ——

  static String get _contentTypes => _xml('''<Types
    xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels"
      ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
      ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');

  static String get _rootRels => _xml('''<Relationships
    xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
      Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
      Target="word/document.xml"/>
</Relationships>''');

  static String _titleParagraph(String title) => _paragraph(
    runs: [_run(title, sz: 32, bold: true, color: _bodyHex)],
    center: true,
    after: 120,
  );

  static String _paragraph({
    required List<String> runs,
    bool center = false,
    int after = 0,
  }) {
    final jc = center ? '<w:jc w:val="center"/>' : '';
    return '''    <w:p>
      <w:pPr><w:spacing w:after="$after"/>$jc</w:pPr>
${runs.join()}    </w:p>
''';
  }

  static String _run(
    String text, {
    String? color,
    int sz = 21,
    bool bold = false,
  }) {
    final boldXml = bold ? '<w:b/>' : '';
    final colorXml = color == null ? '' : '<w:color w:val="$color"/>';
    return '''      <w:r>
        <w:rPr>$boldXml<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"
            w:eastAsia="Microsoft YaHei"/>$colorXml<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>
        <w:t xml:space="preserve">${_escape(text)}</w:t>
      </w:r>
''';
  }

  /// XML 五大实体转义；同时剔除控制字符（Word 对非法字符会拒开文档）。
  static String _escape(String s) {
    final sb = StringBuffer();
    for (final code in s.codeUnits) {
      if (code == 0x26) {
        sb.write('&amp;');
      } else if (code == 0x3C) {
        sb.write('&lt;');
      } else if (code == 0x3E) {
        sb.write('&gt;');
      } else if (code == 0x22) {
        sb.write('&quot;');
      } else if (code == 0x27) {
        sb.write('&apos;');
      } else if (code >= 0x20 || code == 0x09) {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  static String _xml(String body) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n$body';
}
