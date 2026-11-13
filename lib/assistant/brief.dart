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

String _plural(int n, String one, String many) => n == 1 ? one : many;

/// The brief Nox writes by himself, without any AI: works offline.
String offlineBrief(TodayData data, DateTime now) {
  final lines = <String>['${_greeting(now)} ! Nous sommes ${frenchDate(now)}.'];

  final weather = data.weather;
  if (weather != null) {
    final umbrella = _wet.contains(weather.condition) ? ' Pense au parapluie.' : '';
    lines.add('Météo : ${weatherLabel(weather)}.$umbrella');
  }

  final allDay = [for (final e in data.events) if (e.allDay) e];
  final timed = [for (final e in data.events) if (!e.allDay && e.end.isAfter(now)) e];
  if (data.events.isEmpty) {
    lines.add('Agenda : rien de prévu aujourd\'hui.');
  } else {
    final parts = <String>[];
    if (allDay.isNotEmpty) {
      parts.add('toute la journée, ${allDay.map((e) => e.title).join(', ')}');
    }
    if (timed.isNotEmpty) {
      final next = timed.first;
      final count = timed.length;
      final when = next.start.isAfter(now) ? 'à ${hhmm(next.start)}' : 'en cours';
      parts.add('$count rendez-vous, '
          '${_plural(count, 'à savoir', 'le prochain')} « ${next.title} » $when');
    } else if (allDay.isEmpty) {
      parts.add('plus rien de prévu');
    }
    lines.add('Agenda : ${parts.join(' ; ')}.');
  }

  final tasks = data.tasks;
  if (tasks.isEmpty) {
    lines.add('Tâches : aucune en attente.');
  } else {
    final more = tasks.length - 1;
    lines.add('Tâches : « ${tasks.first} »'
        '${more > 0 ? ' et $more ${_plural(more, 'autre', 'autres')}' : ''}.');
  }
  return lines.join('\n');
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
      'Rédige en français, en tutoyant, le brief de début de journée de ton '
      'humain : 3 à 5 phrases courtes, sans liste ni titre ni emoji, '
      'en commençant par une salutation adaptée à l\'heure. Signale ce qui '
      'demande de l\'attention (premier rendez-vous, météo qui impose de '
      's\'équiper, tâches). N\'invente rien au-delà de ces données :\n'
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
