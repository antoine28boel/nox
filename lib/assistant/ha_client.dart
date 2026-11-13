import 'dart:convert';
import 'dart:io';

import 'brief.dart';
import 'today.dart';

/// A problem Nox can explain to the user (wrong token, unexpected answer…).
class HaException implements Exception {
  const HaException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to Home Assistant's REST API with a long-lived access token.
class HaClient {
  const HaClient(this.baseUrl, this.token);

  /// As returned by [normalizeHaUrl].
  final String baseUrl;
  final String token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  Future<Object?> _request(String method, Uri uri,
      {Object? body, Duration timeout = const Duration(seconds: 20)}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'nox';
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const HaException('Jeton refusé par Home Assistant.');
      }
      if (response.statusCode != 200) {
        throw HaException('Home Assistant a répondu ${response.statusCode}.');
      }
      try {
        return jsonDecode(text);
      } on FormatException {
        // Typically a login page put in front of Home Assistant.
        throw const HaException("Cette adresse ne répond pas comme Home Assistant.");
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Checks the address and the token. Throws if either is wrong.
  Future<void> ping() async {
    final answer = await _request('GET', _uri('/api/'));
    if (answer is! Map || answer['message'] is! String) {
      throw const HaException("Cette adresse ne répond pas comme Home Assistant.");
    }
  }

  /// Fetches today's agenda, the weather and the tasks still to do.
  Future<TodayData> fetchToday(DateTime now) async {
    final found = discoverEntities(await _request('GET', _uri('/api/states')));

    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final range = {
      'start': dayStart.toUtc().toIso8601String(),
      'end': dayEnd.toUtc().toIso8601String(),
    };

    final events = <AgendaEvent>[];
    for (final calendar in found.calendars.entries) {
      try {
        final json = await _request('GET', _uri('/api/calendars/${calendar.key}', range));
        events.addAll(parseCalendarEvents(json, calendar: calendar.value));
      } on HaException {
        // One broken calendar must not hide the others.
      }
    }
    sortEvents(events);

    final tasks = <String>[];
    for (final todo in found.todos.keys) {
      try {
        final json = await _request(
          'POST',
          _uri('/api/services/todo/get_items', const {'return_response': ''}),
          body: {'entity_id': todo, 'status': 'needs_action'},
        );
        tasks.addAll(parseTodoItems(json, todo));
      } on HaException {
        // Same for a broken list.
      }
    }

    return TodayData(fetchedAt: now, weather: found.weather, events: events, tasks: tasks);
  }

  /// Asks Home Assistant's AI (its default "AI task" entity) to write the
  /// morning brief. Null when no AI is set up or it fails: Nox then writes
  /// it himself.
  Future<String?> aiBrief(TodayData data, DateTime now) async {
    try {
      final json = await _request(
        'POST',
        _uri('/api/services/ai_task/generate_data', const {'return_response': ''}),
        body: {'task_name': 'Brief du matin de Nox', 'instructions': briefInstructions(data, now)},
        timeout: const Duration(seconds: 60),
      );
      return parseAiTaskText(json);
    } catch (_) {
      return null;
    }
  }
}
