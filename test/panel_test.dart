import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/today_panel.dart';

void main() {
  testWidgets('the panel shows its tabs and switches between them', (tester) async {
    tester.view.physicalSize = kPanelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPanel(
            now: DateTime(2026, 11, 15, 9),
            data: null,
            configured: true,
            haUrl: 'https://ha.test',
            onRefresh: () {},
            onClose: () {},
            onSaveSettings: (_, _) async => null,
            onSaveVikunja: (_, _) async => null,
            onSpotifyLogin: (_) async => null,
            onSpotifyLogout: () {},
          ),
        ),
      ),
    );
    for (final label in ['Suivi', 'Musique', 'Maison', 'Agenda', 'Tâches', 'Budget']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('relié à Vikunja'), findsOneWidget);
    await tester.tap(find.text('Maison'));
    await tester.pumpAndSettle();
    expect(find.textContaining('relié à Home Assistant'), findsOneWidget);
    await tester.tap(find.text('Musique'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ni à Spotify'), findsOneWidget);
    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(find.textContaining('relié à Actual Budget'), findsOneWidget);
  });
}
