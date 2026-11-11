import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/today.dart';

void main() {
  group('discoverEntities', () {
    test('finds calendars, to-do lists and the first usable weather', () {
      final found = discoverEntities([
        {
          'entity_id': 'calendar.famille',
          'state': 'off',
          'attributes': {'friendly_name': 'Famille'},
        },
        {'entity_id': 'calendar.travail', 'state': 'on'},
        {
          'entity_id': 'todo.courses',
          'state': '3',
          'attributes': {'friendly_name': 'Courses'},
        },
        {'entity_id': 'weather.cassee', 'state': 'unavailable'},
        {
          'entity_id': 'weather.maison',
          'state': 'rainy',
          'attributes': {'temperature': 11.6, 'temperature_unit': '°C'},
        },
        {'entity_id': 'weather.autre', 'state': 'sunny'},
        {'entity_id': 'light.salon', 'state': 'on'},
        'garbage',
      ]);
      expect(found.calendars, {'calendar.famille': 'Famille', 'calendar.travail': 'calendar.travail'});
      expect(found.todos, {'todo.courses': 'Courses'});
      expect(found.weather!.condition, 'rainy');
      expect(weatherLabel(found.weather!), 'Pluie · 12 °C');
    });

    test('survives an unexpected answer', () {
      final found = discoverEntities({'message': 'nope'});
      expect(found.calendars, isEmpty);
      expect(found.weather, isNull);
    });
  });

  group('parseCalendarEvents', () {
    test('reads timed and all-day events', () {
      final events = parseCalendarEvents([
        {
          'summary': ' Dentiste ',
          'start': {'dateTime': '2026-11-11T09:00:00+01:00'},
          'end': {'dateTime': '2026-11-11T09:30:00+01:00'},
        },
        {
          'summary': 'Anniversaire',
          'start': {'date': '2026-11-11'},
          'end': {'date': '2026-11-12'},
        },
        {
          'start': {'dateTime': '2026-11-11T07:00:00+01:00'},
        },
        {'summary': 'sans date'},
      ], calendar: 'Famille');

      expect(events, hasLength(3));
      expect(events[0].title, 'Dentiste');
      expect(events[0].allDay, isFalse);
      expect(events[0].start.toUtc(), DateTime.utc(2026, 11, 11, 8));
      expect(events[0].end.toUtc(), DateTime.utc(2026, 11, 11, 8, 30));
      expect(events[0].calendar, 'Famille');
      expect(events[1].allDay, isTrue);
      expect(events[1].start, DateTime(2026, 11, 11));
      expect(eventTime(events[1]), 'Toute la journée');
      expect(events[2].title, '(sans titre)');
      expect(events[2].end, events[2].start);

      sortEvents(events);
      expect([for (final e in events) e.title], ['Anniversaire', '(sans titre)', 'Dentiste']);
    });

    test('returns nothing for an unexpected answer', () {
      expect(parseCalendarEvents({'message': 'Entity not found'}), isEmpty);
      expect(parseCalendarEvents(null), isEmpty);
    });
  });

  test('parseTodoItems keeps what is still to do', () {
    final json = {
      'changed_states': <Object>[],
      'service_response': {
        'todo.courses': {
          'items': [
            {'summary': 'Pain', 'uid': '1', 'status': 'needs_action'},
            {'summary': 'Lait', 'uid': '2', 'status': 'completed'},
            {'summary': ' Œufs ', 'uid': '3'},
            {'summary': '  ', 'uid': '4'},
          ],
        },
      },
    };
    expect(parseTodoItems(json, 'todo.courses'), ['Pain', 'Œufs']);
    expect(parseTodoItems(json, 'todo.autre'), isEmpty);
    expect(parseTodoItems('nope', 'todo.courses'), isEmpty);
  });

  test('the offline cache round-trips', () {
    final data = TodayData(
      fetchedAt: DateTime.utc(2026, 11, 11, 7, 15).toLocal(),
      weather: const WeatherNow(condition: 'sunny', temperature: 4),
      events: [
        AgendaEvent(
          title: 'Dentiste',
          start: DateTime.utc(2026, 11, 11, 8).toLocal(),
          end: DateTime.utc(2026, 11, 11, 8, 30).toLocal(),
          allDay: false,
          calendar: 'Famille',
        ),
      ],
      tasks: const ['Pain'],
    );
    final back = TodayData.fromJson(jsonDecode(jsonEncode(data.toJson())))!;
    expect(back.fetchedAt, data.fetchedAt);
    expect(weatherLabel(back.weather!), 'Ensoleillé · 4 °C');
    expect(back.events.single.title, 'Dentiste');
    expect(back.events.single.start, data.events.single.start);
    expect(back.events.single.calendar, 'Famille');
    expect(back.tasks, ['Pain']);
    expect(TodayData.fromJson({'fetchedAt': 'pas une date'}), isNull);
    expect(TodayData.fromJson('nope'), isNull);
  });

  test('formats dates and times in French', () {
    expect(frenchDate(DateTime(2026, 11, 11)), 'mercredi 11 novembre');
    expect(frenchDate(DateTime(2026, 8, 1)), 'samedi 1er août');
    expect(hhmm(DateTime(2026, 1, 1, 9, 5)), '09:05');
    expect(weatherLabel(const WeatherNow(condition: 'tornado')), 'tornado');
  });

  test('normalizeHaUrl cleans what the user types', () {
    expect(normalizeHaUrl(' ha.exemple.fr '), 'https://ha.exemple.fr');
    expect(normalizeHaUrl('https://ha.exemple.fr/'), 'https://ha.exemple.fr');
    expect(normalizeHaUrl('http://192.168.1.10:8123'), 'http://192.168.1.10:8123');
    expect(normalizeHaUrl('https://exemple.fr/ha//'), 'https://exemple.fr/ha');
    expect(normalizeHaUrl(''), isNull);
    expect(normalizeHaUrl('ftp://ha.exemple.fr'), isNull);
  });
}
