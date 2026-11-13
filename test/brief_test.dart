import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/brief.dart';
import 'package:nox/assistant/today.dart';

void main() {
  final morning = DateTime(2026, 11, 13, 8, 30);

  group('briefDue', () {
    test('due once a day, from 5 am', () {
      expect(briefDue(DateTime(2026, 11, 13, 4, 59), null), isFalse);
      expect(briefDue(morning, null), isTrue);
      expect(briefDue(morning, '2026-11-12'), isTrue);
      expect(briefDue(morning, '2026-11-13'), isFalse);
    });
  });

  group('offlineBrief', () {
    test('tells the weather, the next appointment and the tasks', () {
      final data = TodayData(
        fetchedAt: morning,
        weather: const WeatherNow(condition: 'rainy', temperature: 11.6),
        events: [
          AgendaEvent(
              title: 'Anniversaire de Léa',
              start: DateTime(2026, 11, 13),
              end: DateTime(2026, 11, 14),
              allDay: true),
          AgendaEvent(
              title: 'Réunion',
              start: DateTime(2026, 11, 13, 7),
              end: DateTime(2026, 11, 13, 8),
              allDay: false),
          AgendaEvent(
              title: 'Dentiste',
              start: DateTime(2026, 11, 13, 10),
              end: DateTime(2026, 11, 13, 11),
              allDay: false),
          AgendaEvent(
              title: 'Sport',
              start: DateTime(2026, 11, 13, 18),
              end: DateTime(2026, 11, 13, 19),
              allDay: false),
        ],
        tasks: const ['Appeler la banque', 'Courses', 'Lessive'],
      );
      expect(
        offlineBrief(data, morning),
        'Bonjour ! Nous sommes vendredi 13 novembre.\n'
        'Météo : Pluie · 12 °C. Pense au parapluie.\n'
        'Agenda : toute la journée, Anniversaire de Léa ; '
        '2 rendez-vous, le prochain « Dentiste » à 10:00.\n'
        'Tâches : « Appeler la banque » et 2 autres.',
      );
    });

    test('an empty day', () {
      final data = TodayData(fetchedAt: morning);
      expect(
        offlineBrief(data, DateTime(2026, 11, 13, 19)),
        'Bonsoir ! Nous sommes vendredi 13 novembre.\n'
        'Agenda : rien de prévu aujourd\'hui.\n'
        'Tâches : aucune en attente.',
      );
    });
  });

  test('briefInstructions carry the day\'s data', () {
    final data = TodayData(
      fetchedAt: morning,
      events: [
        AgendaEvent(
            title: 'Dentiste',
            start: DateTime(2026, 11, 13, 10),
            end: DateTime(2026, 11, 13, 11),
            allDay: false,
            calendar: 'Perso'),
      ],
      tasks: const ['Courses'],
    );
    final text = briefInstructions(data, morning);
    expect(text, contains('Date : vendredi 13 novembre, il est 08:30.'));
    expect(text, contains('Agenda : 10:00 – 11:00 — Dentiste (Perso).'));
    expect(text, contains('Tâche à faire : Courses.'));
  });

  test('parseAiTaskText', () {
    expect(
      parseAiTaskText({
        'changed_states': [],
        'service_response': {'conversation_id': 'x', 'data': '  Bonjour toi !  '},
      }),
      'Bonjour toi !',
    );
    expect(parseAiTaskText({'service_response': {'data': '   '}}), isNull);
    expect(parseAiTaskText({'message': 'nope'}), isNull);
  });

  test('Brief survives a round trip and remembers it was read', () {
    const brief = Brief(day: '2026-11-13', text: 'Salut', byAi: true);
    final back = Brief.fromJson(brief.markRead().toJson())!;
    expect(back.day, '2026-11-13');
    expect(back.text, 'Salut');
    expect(back.byAi, isTrue);
    expect(back.read, isTrue);
    expect(Brief.fromJson('garbage'), isNull);
  });
}
