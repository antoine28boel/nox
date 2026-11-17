import 'dart:convert';
import 'dart:io';

import 'budget.dart';

/// A problem Nox can explain to the user (wrong key, unknown budget…).
class ActualException implements Exception {
  const ActualException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Accepts "actual.local:5007", "http://actual.local:5007/" or ".../v1":
/// returns the base address of actual-http-api, or null.
String? normalizeActualUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'/v1$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Talks to Actual Budget through actual-http-api
/// (github.com/jhonderson/actual-http-api), which has the API key.
class ActualClient {
  const ActualClient(this.baseUrl, this.apiKey, this.syncId, {this.password = ''});

  /// As returned by [normalizeActualUrl].
  final String baseUrl;
  final String apiKey;

  /// The budget's "Sync ID" (Actual → Settings → Advanced).
  final String syncId;

  /// The budget's end-to-end encryption password, if it has one.
  final String password;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path}/v1/budgets/${Uri.encodeComponent(syncId)}$path',
      queryParameters: query,
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'nox';
    // The first call of a budget downloads it from the Actual server.
    const timeout = Duration(seconds: 40);
    try {
      final request = await client.openUrl(method, _uri(path, query));
      request.headers.set('x-api-key', apiKey);
      if (password.isNotEmpty) request.headers.set('budget-encryption-password', password);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        throw ActualException('Clé d\'API refusée par actual-http-api.', status: status);
      }
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        throw const ActualException('Cette adresse ne répond pas comme actual-http-api.');
      }
      if (status != 200 && status != 201) {
        final detail = json is Map ? (json['error'] ?? json['message']) : null;
        throw ActualException(
          detail != null ? 'Actual : $detail' : 'actual-http-api a répondu $status.',
          status: status,
        );
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  /// Checks the address, the key and the budget. Throws if one is wrong.
  Future<void> ping() async {
    final json = await _get('/accounts');
    if (unwrapData(json) is! List) {
      throw const ActualException('Cette adresse ne répond pas comme actual-http-api.');
    }
  }

  /// Balances, this month's envelopes and the operations of the last [days].
  Future<Finances> fetchFinances(DateTime now, {int days = 30}) async {
    final results = await Future.wait([
      _get('/accounts'),
      _get('/months/${monthKey(now)}'),
      _get('/payees'),
    ]);
    final month = parseMonth(results[1]);
    final payees = parsePayees(results[2]);
    final categories = {for (final e in month.envelopes) e.id: e.name};
    final since = dayKey(now.subtract(Duration(days: days)));

    final accounts = await Future.wait([
      for (final a in parseAccounts(results[0]))
        _get('/accounts/${a.id}/balance').then((b) => a.withBalance(_int(unwrapData(b)))),
    ]);
    final perAccount = await Future.wait([
      for (final a in accounts)
        if (!a.offBudget)
          _get('/accounts/${a.id}/transactions', {
            'since_date': since,
          }).then((t) => parseOperations(t, payees: payees, categories: categories)),
    ]);
    final operations = perAccount.expand((o) => o).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return Finances(accounts: accounts, month: month, operations: operations);
  }

  /// Adds a spending of [cents] (positive) to an account.
  Future<void> addExpense({
    required String accountId,
    required int cents,
    required DateTime date,
    String payee = '',
    String? categoryId,
    String notes = '',
  }) async {
    await _send(
      'POST',
      '/accounts/$accountId/transactions',
      body: {
        'learnCategories': true,
        'transaction': {
          'account': accountId,
          'date': dayKey(date),
          'amount': -cents,
          if (payee.trim().isNotEmpty) 'payee_name': payee.trim(),
          'category': ?categoryId,
          if (notes.trim().isNotEmpty) 'notes': notes.trim(),
          'cleared': false,
        },
      },
    );
  }

  static int _int(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
}
