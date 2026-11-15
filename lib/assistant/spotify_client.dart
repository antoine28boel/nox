import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'spotify.dart';

/// A problem Nox can explain to the user (no Premium, no device…).
class SpotifyException implements Exception {
  const SpotifyException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Opens [uri] in the default browser.
Future<void> openInBrowser(Uri uri) async {
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [uri.toString()]);
  } else {
    await Process.start('xdg-open', [uri.toString()]);
  }
}

const _page = '''<!doctype html><meta charset="utf-8"><title>Nox</title>
<body style="font-family:sans-serif;background:#2B211A;color:#F5E9D3;text-align:center;padding-top:20vh">
<h1>%s</h1><p>Tu peux fermer cet onglet.</p></body>''';

/// Talks to the Spotify Web API for the user who logged in with [login].
class SpotifyClient {
  SpotifyClient(this.clientId, this._refreshToken, {this.onNewRefreshToken});

  final String clientId;
  String _refreshToken;

  /// Spotify may rotate the refresh token: it must then be saved again.
  final void Function(String token)? onNewRefreshToken;

  String? _access;
  DateTime _expires = DateTime(0);

  /// Lets the user log in in the browser, then returns the refresh token.
  /// Throws a [SpotifyException] if they refuse or take too long.
  static Future<String> login(String clientId) async {
    final verifier = pkceVerifier();
    final state = pkceVerifier().substring(0, 16);
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, kSpotifyPort);
    } on SocketException {
      throw const SpotifyException('Le port $kSpotifyPort est déjà utilisé sur ce PC.');
    }
    try {
      await openInBrowser(spotifyAuthorizeUri(clientId, pkceChallenge(verifier), state));
      await for (final request in server.timeout(const Duration(minutes: 3))) {
        if (request.uri.path != '/callback') {
          request.response.statusCode = 404;
          await request.response.close();
          continue;
        }
        final q = request.uri.queryParameters;
        final ok = q['state'] == state && q['code'] != null;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          _page.replaceFirst('%s', ok ? 'Nox est relié à Spotify' : 'Connexion à Spotify refusée'),
        );
        await request.response.close();
        if (!ok) throw const SpotifyException('Connexion à Spotify refusée.');
        final json = await _token({
          'grant_type': 'authorization_code',
          'code': q['code']!,
          'redirect_uri': kSpotifyRedirect,
          'client_id': clientId,
          'code_verifier': verifier,
        });
        final refresh = json['refresh_token'];
        if (refresh is! String) throw const SpotifyException('Réponse inattendue de Spotify.');
        return refresh;
      }
      throw const SpotifyException('Connexion à Spotify interrompue.');
    } on TimeoutException {
      throw const SpotifyException('Connexion à Spotify abandonnée (délai dépassé).');
    } finally {
      await server.close(force: true);
    }
  }

  static Future<Map> _token(Map<String, String> form) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.https('accounts.spotify.com', '/api/token'));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      final json = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode != 200 || json is! Map) {
        final reason = json is Map ? json['error_description'] ?? json['error'] : null;
        throw SpotifyException(
          reason == 'Invalid client' || reason == 'invalid_client'
              ? 'Client ID Spotify inconnu.'
              : 'Spotify a refusé la connexion${reason is String ? ' ($reason)' : ''}. '
                    'Reconnecte-toi dans Réglages.',
          status: response.statusCode,
        );
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _accessToken() async {
    final current = _access;
    if (current != null && DateTime.now().isBefore(_expires)) return current;
    final json = await _token({
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken,
      'client_id': clientId,
    });
    final access = json['access_token'];
    if (access is! String) throw const SpotifyException('Réponse inattendue de Spotify.');
    final expires = json['expires_in'];
    _access = access;
    _expires = DateTime.now().add(Duration(seconds: (expires is int ? expires : 3600) - 60));
    final rotated = json['refresh_token'];
    if (rotated is String && rotated != _refreshToken) {
      _refreshToken = rotated;
      onNewRefreshToken?.call(rotated);
    }
    return access;
  }

  Future<Object?> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retry = true,
  }) async {
    final token = await _accessToken();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'nox';
    try {
      final request = await client.openUrl(method, Uri.https('api.spotify.com', '/v1$path', query));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      } else if (method != 'GET') {
        request.headers.contentLength = 0;
      }
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      final status = response.statusCode;
      if (status == 401 && retry) {
        _access = null;
        return await _api(method, path, query: query, body: body, retry: false);
      }
      if (status == 204 || text.isEmpty) return null;
      Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
      if (status >= 200 && status < 300) return json;
      final error = json is Map ? json['error'] : null;
      final reason = error is Map ? error['reason'] : null;
      throw SpotifyException(switch ((status, reason)) {
        (403, 'PREMIUM_REQUIRED') => 'Spotify Premium est nécessaire pour piloter la lecture.',
        (404, _) || (_, 'NO_ACTIVE_DEVICE') =>
          'Aucun appareil Spotify actif : ouvre Spotify ou choisis un appareil.',
        (429, _) => 'Spotify demande de patienter un peu.',
        (401, _) => 'Session Spotify expirée : reconnecte-toi dans Réglages.',
        _ => 'Spotify a répondu $status.',
      }, status: status);
    } finally {
      client.close(force: true);
    }
  }

  /// What is playing, or null when nothing plays anywhere.
  Future<SpotifyPlayback?> playback() async =>
      parsePlayback(await _api('GET', '/me/player', query: const {'additional_types': 'episode'}));

  Future<List<SpotifyDevice>> devices() async =>
      parseDevices(await _api('GET', '/me/player/devices'));

  Future<List<SpotifyItem>> playlists() async =>
      parsePlaylists(await _api('GET', '/me/playlists', query: const {'limit': '50'}));

  Future<List<SpotifyItem>> search(String text) async => parseSearch(
    await _api('GET', '/search', query: {'q': text, 'type': 'track,playlist', 'limit': '8'}),
  );

  Map<String, String>? _on(String? device) => device == null ? null : {'device_id': device};

  /// Resumes, or plays [item] (a track or a playlist), on [device] if given.
  Future<void> play({SpotifyItem? item, String? device}) => _api(
    'PUT',
    '/me/player/play',
    query: _on(device),
    body: item == null
        ? null
        : item.isTrack
        ? {
            'uris': [item.uri],
          }
        : {'context_uri': item.uri},
  );

  Future<void> pause() => _api('PUT', '/me/player/pause');
  Future<void> next() => _api('POST', '/me/player/next');
  Future<void> previous() => _api('POST', '/me/player/previous');

  Future<void> setVolume(int percent) =>
      _api('PUT', '/me/player/volume', query: {'volume_percent': '${percent.clamp(0, 100)}'});

  Future<void> setShuffle(bool on) => _api('PUT', '/me/player/shuffle', query: {'state': '$on'});

  Future<void> seek(int ms) =>
      _api('PUT', '/me/player/seek', query: {'position_ms': '${ms < 0 ? 0 : ms}'});

  /// Moves the playback to [device] and keeps playing.
  Future<void> transfer(String device) => _api(
    'PUT',
    '/me/player',
    body: {
      'device_ids': [device],
      'play': true,
    },
  );
}
