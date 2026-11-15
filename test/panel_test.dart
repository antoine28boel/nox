import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/today_panel.dart';

void main() {
  testWidgets('the panel shows its tabs and switches between them', (tester) async {
    tester.view.physicalSize = kPanelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TodayPanel(
          now: DateTime(2026, 11, 15, 9),
          data: null,
          status: '',
          configured: true,
          haUrl: 'https://ha.test',
          onRefresh: () {},
          onClose: () {},
          onSaveSettings: (_, _) async => null,
        ),
      ),
    ));
    for (final label in ['Jour', 'Musique', 'Maison', 'Agenda', 'Tâches']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Maison'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pas encore relié'), findsOneWidget);
  });
}
