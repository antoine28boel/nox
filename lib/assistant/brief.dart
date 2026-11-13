// The morning brief: what Nox brings at the first sign of life of the day.
//
// Pure Dart: the simple offline text, the request sent to Home Assistant's
// AI, and when the brief is due.

import 'today.dart';

/// Before this hour, being at the PC doesn't count as the start of the day.
const kBriefFromHour = 5;

/// "2026-11-13": the day a brief belongs to.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Whether today's brief still has to be brought. [lastDay] is the
/// [dayKey] of the last brief.
bool briefDue(DateTime now, String? lastDay) =>
    now.hour >= kBriefFromHour && lastDay != dayKey(now);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether [data] describes the day of [now] (and not yesterday's cache).
bool isFromToday(TodayData data, DateTime now) => _sameDay(data.fetchedAt, now);

String _greeting(DateTime now) {
  if (now.hour < 12) return 'Bonjour';
  if (now.hour < 18) return 'Bon après-midi';
  return 'Bonsoir';
}

const _wet = {'rainy', 'pouring', 'lightning-rainy', 'hail', 'snowy-rainy'};

/// The brief Nox writes by himself, without any AI: works offline. A short
/// word on what matters; the details are in the panel's sections.
String offlineBrief(TodayData data, DateTime now) {
  final words = <String>['${_greeting(now)} !'];

  final timed = [for (final e in data.events) if (!e.allDay && e.end.isAfter(now)) e];
  if (timed.isNotEmpty) {
    final next = timed.first;
    words.add(next.start.isAfter(now)
        ? 'Prochain rendez-vous à ${hhmm(next.start)} : ${next.title}.'
        : '« ${next.title} » est en cours.');
  } else if (data.events.isEmpty) {
    words.add('Rien à l\'agenda.');
  } else {
    words.add('Pas de rendez-vous à heure fixe.');
  }

  final weather = data.weather;
  if (weather != null) {
    final t = weather.temperature;
    if (_wet.contains(weather.condition)) {
      words.add('Pense au parapluie.');
    } else if (t != null && t <= 2) {
      words.add('Il fait froid, couvre-toi.');
    }
  }

  final n = data.tasks.length;
  if (n > 0) words.add(n == 1 ? 'Une tâche t\'attend.' : '$n tâches t\'attendent.');
  return words.join(' ');
}

/// What Home Assistant's AI is asked to write, with the day's data.
String briefInstructions(TodayData data, DateTime now) {
  final facts = <String>[
    'Date : ${frenchDate(now)}, il est ${hhmm(now)}.',
    if (data.weather != null) 'Météo : ${weatherLabel(data.weather!)}.',
    if (data.events.isEmpty) 'Agenda : rien.',
    for (final e in data.events)
      'Agenda : ${eventTime(e)} — ${e.title}'
          '${e.calendar.isEmpty ? '' : ' (${e.calendar})'}.',
    if (data.tasks.isEmpty) 'Tâches : aucune.',
    for (final t in data.tasks) 'Tâche à faire : $t.',
  ];
  return 'Tu es Nox, un petit hibou assistant, bienveillant et un peu malicieux. '
      'Rédige en français, en tutoyant, le mot de début de journée de ton '
      'humain : 1 à 3 phrases courtes, sans liste ni titre ni emoji, '
      'en commençant par une salutation adaptée à l\'heure. L\'agenda, la '
      'météo et les tâches sont déjà affichés en détail juste en dessous : '
      'ne les énumère pas, ne redonne pas la date, dis seulement ce qui mérite '
      'l\'attention ou un conseil. N\'invente rien au-delà de ces données :\n'
      '${facts.join('\n')}';
}

/// Reads the answer of the `ai_task.generate_data` service: the generated
/// text, or null.
String? parseAiTaskText(Object? json) {
  if (json is! Map) return null;
  final response = json['service_response'];
  if (response is! Map) return null;
  final text = response['data'];
  if (text is! String) return null;
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The brief of a day, as kept in the preferences.
class Brief {
  const Brief({required this.day, required this.text, required this.byAi, this.read = false});

  /// [dayKey] of the day it is about.
  final String day;
  final String text;

  /// Written by Home Assistant's AI (otherwise by [offlineBrief]).
  final bool byAi;

  /// Whether it was shown in the panel.
  final bool read;

  Brief markRead() => Brief(day: day, text: text, byAi: byAi, read: true);

  Map<String, Object?> toJson() => {'day': day, 'text': text, 'byAi': byAi, 'read': read};

  static Brief? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = json['day'];
    final text = json['text'];
    if (day is! String || text is! String) return null;
    return Brief(day: day, text: text, byAi: json['byAi'] == true, read: json['read'] == true);
  }
}
