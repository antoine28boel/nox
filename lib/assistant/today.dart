// What Nox knows about today: agenda, weather, tasks.
//
// Pure Dart: parsing of Home Assistant's answers and the offline cache
// format, so it can be tested without a network.

class AgendaEvent {
  const AgendaEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.calendar = '',
  });

  final String title;

  /// Local time.
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Name of the calendar it comes from.
  final String calendar;

  Map<String, Object?> toJson() => {
        'title': title,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'allDay': allDay,
        'calendar': calendar,
      };

  static AgendaEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    final start = json['start'];
    final end = json['end'];
    if (title is! String || start is! String || end is! String) return null;
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    if (s == null || e == null) return null;
    final calendar = json['calendar'];
    return AgendaEvent(
      title: title,
      start: s.toLocal(),
      end: e.toLocal(),
      allDay: json['allDay'] == true,
      calendar: calendar is String ? calendar : '',
    );
  }
}

class WeatherNow {
  const WeatherNow({required this.condition, this.temperature, this.unit = '°C'});

  /// Home Assistant condition ("sunny", "rainy"…).
  final String condition;
  final double? temperature;
  final String unit;

  Map<String, Object?> toJson() =>
      {'condition': condition, 'temperature': temperature, 'unit': unit};

  static WeatherNow? fromJson(Object? json) {
    if (json is! Map) return null;
    final condition = json['condition'];
    if (condition is! String) return null;
    final temperature = json['temperature'];
    final unit = json['unit'];
    return WeatherNow(
      condition: condition,
      temperature: temperature is num ? temperature.toDouble() : null,
      unit: unit is String ? unit : '°C',
    );
  }
}

/// Everything shown in the "Aujourd'hui" panel, as last fetched.
class TodayData {
  const TodayData({
    required this.fetchedAt,
    this.weather,
    this.events = const [],
    this.tasks = const [],
  });

  final DateTime fetchedAt;
  final WeatherNow? weather;
  final List<AgendaEvent> events;
  final List<String> tasks;

  Map<String, Object?> toJson() => {
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'weather': weather?.toJson(),
        'events': [for (final e in events) e.toJson()],
        'tasks': tasks,
      };

  static TodayData? fromJson(Object? json) {
    if (json is! Map) return null;
    final fetchedAt = json['fetchedAt'];
    if (fetchedAt is! String) return null;
    final at = DateTime.tryParse(fetchedAt);
    if (at == null) return null;
    final events = json['events'];
    final tasks = json['tasks'];
    return TodayData(
      fetchedAt: at.toLocal(),
      weather: WeatherNow.fromJson(json['weather']),
      events: [
        if (events is List)
          for (final e in events)
            ?AgendaEvent.fromJson(e),
      ],
      tasks: [
        if (tasks is List)
          for (final t in tasks)
            if (t is String) t,
      ],
    );
  }
}

/// The Home Assistant entities Nox reads, found in `/api/states`.
class HaEntities {
  const HaEntities({this.calendars = const {}, this.todos = const {}, this.weather});

  /// entity_id → friendly name.
  final Map<String, String> calendars;
  final Map<String, String> todos;
  final WeatherNow? weather;
}

/// Finds calendars, to-do lists and the first weather entity in the answer
/// of `/api/states`.
HaEntities discoverEntities(Object? states) {
  final calendars = <String, String>{};
  final todos = <String, String>{};
  WeatherNow? weather;
  if (states is! List) return const HaEntities();
  for (final s in states) {
    if (s is! Map) continue;
    final id = s['entity_id'];
    if (id is! String) continue;
    final attrs = s['attributes'];
    final friendly = attrs is Map ? attrs['friendly_name'] : null;
    final name = friendly is String ? friendly : id;
    if (id.startsWith('calendar.')) {
      calendars[id] = name;
    } else if (id.startsWith('todo.')) {
      todos[id] = name;
    } else if (id.startsWith('weather.') && weather == null) {
      final state = s['state'];
      if (state is! String || state == 'unavailable' || state == 'unknown') continue;
      final temperature = attrs is Map ? attrs['temperature'] : null;
      final unit = attrs is Map ? attrs['temperature_unit'] : null;
      weather = WeatherNow(
        condition: state,
        temperature: temperature is num ? temperature.toDouble() : null,
        unit: unit is String ? unit : '°C',
      );
    }
  }
  return HaEntities(calendars: calendars, todos: todos, weather: weather);
}

DateTime? _when(Object? value) {
  if (value is! Map) return null;
  final dateTime = value['dateTime'];
  if (dateTime is String) return DateTime.tryParse(dateTime)?.toLocal();
  final date = value['date'];
  // A bare date has no time zone: it is parsed as local midnight.
  if (date is String) return DateTime.tryParse(date);
  return null;
}

/// Reads the answer of `/api/calendars/<entity>?start=…&end=…`.
List<AgendaEvent> parseCalendarEvents(Object? json, {String calendar = ''}) {
  final events = <AgendaEvent>[];
  if (json is! List) return events;
  for (final e in json) {
    if (e is! Map) continue;
    final start = _when(e['start']);
    if (start == null) continue;
    final rawStart = e['start'];
    final summary = e['summary'];
    events.add(AgendaEvent(
      title: summary is String && summary.trim().isNotEmpty ? summary.trim() : '(sans titre)',
      start: start,
      end: _when(e['end']) ?? start,
      allDay: rawStart is Map && rawStart['dateTime'] == null,
      calendar: calendar,
    ));
  }
  return events;
}

/// All-day events first, then by start time.
void sortEvents(List<AgendaEvent> events) {
  events.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.title.compareTo(b.title);
  });
}

/// Reads the answer of the `todo.get_items` service for [entityId]: the
/// summaries of the items still to do.
List<String> parseTodoItems(Object? json, String entityId) {
  final tasks = <String>[];
  if (json is! Map) return tasks;
  final response = json['service_response'];
  if (response is! Map) return tasks;
  final list = response[entityId];
  final items = list is Map ? list['items'] : null;
  if (items is! List) return tasks;
  for (final item in items) {
    if (item is! Map) continue;
    final summary = item['summary'];
    final status = item['status'];
    if (summary is! String || summary.trim().isEmpty) continue;
    if (status is String && status != 'needs_action') continue;
    tasks.add(summary.trim());
  }
  return tasks;
}

const _conditions = {
  'clear-night': 'Nuit claire',
  'cloudy': 'Nuageux',
  'exceptional': 'Conditions exceptionnelles',
  'fog': 'Brouillard',
  'hail': 'Grêle',
  'lightning': 'Orage',
  'lightning-rainy': 'Orage et pluie',
  'partlycloudy': 'Éclaircies',
  'pouring': 'Forte pluie',
  'rainy': 'Pluie',
  'snowy': 'Neige',
  'snowy-rainy': 'Neige et pluie',
  'sunny': 'Ensoleillé',
  'windy': 'Venteux',
  'windy-variant': 'Venteux et nuageux',
};

/// "Pluie · 12 °C".
String weatherLabel(WeatherNow weather) {
  final condition = _conditions[weather.condition] ?? weather.condition;
  final t = weather.temperature;
  if (t == null) return condition;
  final rounded = t.round();
  return '$condition · $rounded ${weather.unit}';
}

const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', //
  'septembre', 'octobre', 'novembre', 'décembre',
];

/// "mercredi 11 novembre".
String frenchDate(DateTime d) {
  final day = d.day == 1 ? '1er' : '${d.day}';
  return '${_weekdays[d.weekday - 1]} $day ${_months[d.month - 1]}';
}

/// "09:05".
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Toute la journée" or "09:00 – 10:30".
String eventTime(AgendaEvent e) =>
    e.allDay ? 'Toute la journée' : '${hhmm(e.start)} – ${hhmm(e.end)}';

/// Accepts "ha.example.org" or "https://ha.example.org/": returns a clean
/// base URL, or null if it cannot be one.
String? normalizeHaUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: path)
      .toString();
}
