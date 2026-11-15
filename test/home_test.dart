import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/home.dart';
import 'package:nox/assistant/today.dart';

void main() {
  final states = [
    {
      'entity_id': 'media_player.salon',
      'state': 'paused',
      'attributes': {
        'friendly_name': 'Salon',
        'media_title': 'Clair de lune',
        'media_artist': 'Debussy',
        'volume_level': 0.4,
        'supported_features': 1 | 4 | 16 | 32,
      },
    },
    {
      'entity_id': 'media_player.cuisine',
      'state': 'playing',
      'attributes': {'friendly_name': 'Cuisine', 'supported_features': 16384},
    },
    {'entity_id': 'media_player.tv', 'state': 'unavailable', 'attributes': {}},
    {
      'entity_id': 'light.bureau',
      'state': 'on',
      'attributes': {'friendly_name': 'Bureau', 'brightness': 128},
    },
    {'entity_id': 'light.abri', 'state': 'off', 'attributes': {'friendly_name': 'Abri'}},
    {'entity_id': 'scene.film', 'state': 'scening', 'attributes': {'friendly_name': 'Film'}},
    {
      'entity_id': 'climate.salon',
      'state': 'heat',
      'attributes': {'friendly_name': 'Salon', 'current_temperature': 19.5, 'temperature': 20},
    },
    {'entity_id': 'sensor.temp', 'state': '12', 'attributes': {}},
    {'entity_id': 'todo.courses', 'state': '2', 'attributes': {'friendly_name': 'Courses'}},
  ];

  test('media players: playing first, unavailable left out', () {
    final players = parseMediaPlayers(states);
    expect(players.map((p) => p.name), ['Cuisine', 'Salon']);
    final salon = players[1];
    expect(salon.title, 'Clair de lune');
    expect(salon.artist, 'Debussy');
    expect(salon.volume, 0.4);
    expect(salon.canNext && salon.canPrevious && salon.canSetVolume, isTrue);
    expect(players[0].canPause, isTrue);
    expect(players[0].canNext, isFalse);
  });

  test('home devices grouped by domain in a fixed order, sorted by name', () {
    final groups = parseHomeDevices(states);
    expect(groups.keys, ['scene', 'light', 'climate']);
    expect(groups['light']!.map((d) => d.name), ['Abri', 'Bureau']);
    expect(deviceLabel(groups['light']![1]), 'Allumée · 50 %');
    expect(deviceLabel(groups['light']![0]), 'Éteinte');
    expect(deviceLabel(groups['climate']!.single), 'Chauffe · 19,5 °C · → 20 °C');
    expect(groups['light']![0].toggles, isTrue);
    expect(groups['scene']!.single.toggles, isFalse);
  });

  test('to-do lists and their items, open ones first', () {
    expect(parseTodoLists(states), {'todo.courses': 'Courses'});
    final items = parseTodoList({
      'service_response': {
        'todo.courses': {
          'items': [
            {'uid': '1', 'summary': 'Pain', 'status': 'completed'},
            {'uid': '2', 'summary': 'Lait', 'status': 'needs_action', 'due': '2026-11-16'},
            {'summary': 'Sans uid', 'status': 'needs_action'},
          ],
        },
      },
    }, 'todo.courses');
    expect(items.map((i) => i.summary), ['Lait', 'Pain']);
    expect(items[0].done, isFalse);
    expect(items[0].due, '2026-11-16');
    expect(items[1].done, isTrue);
  });

  test('agenda grouped by day, ongoing events on the first day', () {
    final start = DateTime(2026, 11, 15);
    AgendaEvent e(String t, DateTime s, DateTime end) =>
        AgendaEvent(title: t, start: s, end: end, allDay: false);
    final days = groupByDay([
      e('Vacances', DateTime(2026, 11, 13), DateTime(2026, 11, 17)),
      e('Passé', DateTime(2026, 11, 14, 9), DateTime(2026, 11, 14, 10)),
      e('Dentiste', DateTime(2026, 11, 16, 9), DateTime(2026, 11, 16, 10)),
      e('Trop loin', DateTime(2026, 11, 22, 9), DateTime(2026, 11, 22, 10)),
    ], start, 7);
    expect(days.keys, [start, DateTime(2026, 11, 16)]);
    expect(days[start]!.single.title, 'Vacances');
    expect(days[DateTime(2026, 11, 16)]!.single.title, 'Dentiste');
  });
}
