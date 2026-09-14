import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/data/transcript_models.dart';
import 'package:voxdesk/widgets/transcript_view.dart';

void main() {
  testWidgets('点击转写时间戳触发跳转回调（携带段起始秒）', (tester) async {
    final tapped = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TranscriptListView(
          segments: [
            TranscriptSegment(startSec: 12, endSec: 15, text: '第一段'),
            TranscriptSegment(startSec: 75, endSec: 80, text: '第二段'),
          ],
          onTimestampTap: tapped.add,
        ),
      ),
    ));

    await tester.tap(find.text('00:00:12'));
    await tester.tap(find.text('00:01:15'));
    expect(tapped, [12.0, 75.0]);
  });

  testWidgets('未提供回调时时间戳不可点击', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TranscriptListView(
          segments: [TranscriptSegment(startSec: 12, endSec: 15, text: '第一段')],
        ),
      ),
    ));

    expect(find.text('00:00:12'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });
}
