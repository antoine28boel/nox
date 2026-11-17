import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'brief.dart';
import 'ha_dashboard.dart';
import 'home.dart';
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

  Future<Object?> _request(
    String method,
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
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

  /// Every entity's state, as returned by `/api/states`.
  Future<Object?> states() => _request('GET', _uri('/api/states'));

  /// Calls a Home Assistant service, e.g. `light.toggle`.
  Future<void> callService(String domain, String service, Map<String, Object?> data) async {
    await _request('POST', _uri('/api/services/$domain/$service'), body: data);
  }

  /// Opens Home Assistant's WebSocket API (the only one that knows the
  /// dashboards), authenticates, runs [commands] in order and returns their
  /// results. A command that fails gives null.
  Future<List<Object?>> _socket(List<Map<String, Object?>> commands) async {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/api/websocket',
    );
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const HaException('Home Assistant injoignable');
    }
    final results = List<Object?>.filled(commands.length, null);
    try {
      final messages = socket
          .map((m) => m is String ? jsonDecode(m) : null)
          .timeout(const Duration(seconds: 20));
      var next = 0;
      await for (final m in messages) {
        if (m is! Map) continue;
        switch (m['type']) {
          case 'auth_required':
            socket.add(jsonEncode({'type': 'auth', 'access_token': token}));
          case 'auth_invalid':
            throw const HaException('Jeton refusé par Home Assistant.');
          case 'auth_ok':
            for (var i = 0; i < commands.length; i++) {
              socket.add(jsonEncode({'id': i + 1, ...commands[i]}));
            }
          case 'result':
            final id = m['id'];
            if (id is int && id >= 1 && id <= commands.length) {
              if (m['success'] == true) results[id - 1] = m['result'];
              next++;
            }
        }
        if (next == commands.length) break;
      }
    } on TimeoutException {
      throw const HaException('Home Assistant ne répond pas.');
    } finally {
      unawaited(socket.close());
    }
    return results;
  }

  /// The dashboards of Home Assistant, the default one first.
  Future<List<HaDashboardInfo>> fetchDashboards() async {
    final results = await _socket([
      {'type': 'lovelace/dashboards/list'},
    ]);
    return parseDashboards(results.first);
  }

  /// The views of a dashboard ([urlPath] "lovelace" for the default one).
  /// Empty when Home Assistant generates it itself.
  Future<List<DashboardView>> fetchDashboard(String urlPath) async {
    final results = await _socket([
      {'type': 'lovelace/config', 'url_path': urlPath == 'lovelace' ? null : urlPath},
    ]);
    return parseDashboardConfig(results.first);
  }

  /// Address of a picture given by Home Assistant (album cover…).
  Uri pictureUri(String path) {
    final parsed = Uri.parse(path);
    if (parsed.hasScheme) return parsed;
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path}${parsed.path}', query: parsed.query);
  }

  /// The events of every calendar from [start] to [end], sorted.
  Future<List<AgendaEvent>> fetchEvents(DateTime start, DateTime end) async {
    final found = discoverEntities(await states());
    final range = {'start': start.toUtc().toIso8601String(), 'end': end.toUtc().toIso8601String()};
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
    return events;
  }

  /// Every to-do list with all its items (done ones included).
  Future<List<TodoList>> fetchTodoLists() async {
    final lists = <TodoList>[];
    for (final entry in parseTodoLists(await states()).entries) {
      try {
        final json = await _request(
          'POST',
          _uri('/api/services/todo/get_items', const {'return_response': ''}),
          body: {'entity_id': entry.key},
        );
        lists.add(
          TodoList(id: entry.key, name: entry.value, items: parseTodoList(json, entry.key)),
        );
      } on HaException {
        lists.add(TodoList(id: entry.key, name: entry.value));
      }
    }
    return lists;
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
