import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/ha_client.dart';
import 'package:nox/assistant/ha_dashboard.dart';
import 'package:nox/assistant/panel_style.dart';
import 'package:nox/assistant/panel_tabs.dart';

class _FakeHa extends HaClient {
  const _FakeHa() : super('https://ha.test', 'jeton');

  @override
  Future<Object?> states() async => [
    {
      'entity_id': 'light.plafond',
      'state': 'on',
      'attributes': {'friendly_name': 'Plafond du salon avec un nom très long', 'brightness': 128},
    },
    {
      'entity_id': 'switch.prise',
      'state': 'off',
      'attributes': {'friendly_name': 'Prise'},
    },
    {
      'entity_id': 'climate.salon',
      'state': 'heat',
      'attributes': {'friendly_name': 'Salon', 'current_temperature': 19.5, 'temperature': 20},
    },
    {
      'entity_id': 'sensor.humidite',
      'state': '48',
      'attributes': {'unit_of_measurement': '%', 'device_class': 'humidity'},
    },
  ];

  @override
  Future<List<HaDashboardInfo>> fetchDashboards() async => parseDashboards([
    {'url_path': 'maison', 'title': 'Maison', 'mode': 'storage'},
  ]);

  @override
  Future<List<DashboardView>> fetchDashboard(String urlPath) async => parseDashboardConfig({
    'views': [
      {
        'title': 'Salon',
        'cards': [
          {
            'type': 'entities',
            'title': 'Pièce',
            'entities': ['light.plafond', 'switch.prise', 'climate.salon', 'sensor.humidite'],
          },
        ],
      },
      {'title': 'Cuisine', 'cards': []},
    ],
  });
}

void main() {
  testWidgets('the home tab shows the chosen dashboard as tiles', (tester) async {
    tester.view.physicalSize = const Size(380, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final memory = PanelMemory()..dashboard = 'maison';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(client: const _FakeHa(), memory: memory),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('PIÈCE'), findsOneWidget);
    expect(find.text('Allumée · 50 %'), findsOneWidget);
    expect(find.text('48 %'), findsOneWidget);
    expect(find.text('Maison'), findsOneWidget);

    memory.dashboard = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(key: UniqueKey(), client: const _FakeHa(), memory: memory),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('LUMIÈRES'), findsOneWidget);
    expect(find.text('Tous les appareils'), findsOneWidget);
  });
}
