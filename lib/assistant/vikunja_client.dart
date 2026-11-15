import 'dart:convert';
import 'dart:io';

import 'vikunja.dart';

/// A problem Nox can explain to the user (wrong token, unexpected answer…).
class VikunjaException implements Exception {
  const VikunjaException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Accepts "vikunja.local", "https://vikunja.local/" or the API address
/// ".../api/v1": returns the base address of Vikunja, or null.
String? normalizeVikunjaUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'/api/v1$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Talks to Vikunja's REST API with an API token (Settings → API Tokens).
class VikunjaClient {
  const VikunjaClient(this.baseUrl, this.token);

  /// As returned by [normalizeVikunjaUrl].
  final String baseUrl;
  final String token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path}/api/v1$path', queryParameters: query);
  }

  /// The decoded answer and the number of pages announced by Vikunja.
  Future<(Object?, int)> _get(String path, [Map<String, String>? query]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'nox';
    const timeout = Duration(seconds: 20);
    try {
      final request = await client.getUrl(_uri(path, query));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        throw VikunjaException('Jeton refusé par Vikunja.', status: status);
      }
      if (status != 200) throw VikunjaException('Vikunja a répondu $status.', status: status);
      final pages = int.tryParse(response.headers.value('x-pagination-total-pages') ?? '') ?? 1;
      try {
        return (jsonDecode(text), pages);
      } on FormatException {
        throw const VikunjaException('Cette adresse ne répond pas comme Vikunja.');
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Every page of a list.
  Future<List<Object?>> _all(String path, [Map<String, String> query = const {}]) async {
    final all = <Object?>[];
    for (var page = 1; page <= 40; page++) {
      final (json, pages) = await _get(path, {...query, 'per_page': '250', 'page': '$page'});
      if (json is! List || json.isEmpty) break;
      all.addAll(json);
      if (page >= pages) break;
    }
    return all;
  }

  /// Checks the address and the token. Throws if either is wrong.
  Future<void> ping() async {
    final (json, _) = await _get('/projects', const {'per_page': '1'});
    if (json is! List) throw const VikunjaException('Cette adresse ne répond pas comme Vikunja.');
  }

  /// Projects, all their tasks and which ones are in progress.
  Future<Tracking> fetchTracking() async {
    final projects = parseProjects(await _all('/projects'));

    // "/tasks" since Vikunja 1.0, "/tasks/all" before.
    List<Object?> rawTasks;
    try {
      rawTasks = await _all('/tasks');
    } on VikunjaException catch (e) {
      if (e.status != 404 && e.status != 405) rethrow;
      rawTasks = await _all('/tasks/all');
    }
    final tasks = parseTasks(rawTasks);

    final inProgress = <int>{};
    for (final p in projects) {
      try {
        inProgress.addAll(await _inProgressOf(p.id));
      } on VikunjaException {
        // A project without Kanban (or an old Vikunja) only uses labels.
      }
    }
    return buildTracking(projects, tasks, inProgress);
  }

  Future<Set<int>> _inProgressOf(int project) async {
    try {
      final (views, _) = await _get('/projects/$project/views');
      final kanban = kanbanViewId(views);
      if (kanban == null) return const {};
      final (buckets, _) = await _get('/projects/$project/views/$kanban/tasks');
      return inProgressTaskIds(buckets);
    } on VikunjaException catch (e) {
      // Before Vikunja 0.24, buckets belonged to the project.
      if (e.status != 404) rethrow;
      final (buckets, _) = await _get('/projects/$project/buckets');
      return inProgressTaskIds(buckets);
    }
  }
}
