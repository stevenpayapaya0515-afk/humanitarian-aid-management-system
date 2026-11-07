
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aidtrack/main.dart';

void main() {
  testWidgets('AidTrack application loads successfully',
      (WidgetTester tester) async {

    await tester.pumpWidget(const AidTrackApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
