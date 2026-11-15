// What Nox knows about Spotify: playback, devices, playlists, search.
//
// Pure Dart: parsing of the Spotify Web API answers and the PKCE helpers,
// so it can be tested without a network.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Port of the local page Spotify sends the user back to after login.
/// The same address must be declared in the Spotify app (Redirect URIs).
const kSpotifyPort = 8898;
const kSpotifyRedirect = 'http://127.0.0.1:$kSpotifyPort/callback';

const kSpotifyScopes = [
  'user-read-playback-state',
  'user-modify-playback-state',
  'user-read-currently-playing',
  'playlist-read-private',
  'playlist-read-collaborative',
];

/// A random PKCE code verifier (64 characters).
String pkceVerifier([Random? random]) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = random ?? Random.secure();
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

/// The PKCE code challenge of [verifier]: base64url(SHA-256), no padding.
String pkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// The page where the user allows Nox to use their Spotify account.
Uri spotifyAuthorizeUri(String clientId, String challenge, String state) =>
    Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': kSpotifyRedirect,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'scope': kSpotifyScopes.join(' '),
      'state': state,
    });

class SpotifyDevice {
  const SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    this.active = false,
    this.volume,
  });

  final String id;
  final String name;

  /// "Computer", "Smartphone", "Speaker"…
  final String type;
  final bool active;

  /// 0 to 100, or null when the device has no volume control.
  final int? volume;
}

class SpotifyPlayback {
  const SpotifyPlayback({
    this.device,
    this.playing = false,
    this.shuffle = false,
    this.title,
    this.artists,
    this.album,
    this.cover,
    this.progressMs = 0,
    this.durationMs = 0,
  });

  final SpotifyDevice? device;
  final bool playing;
  final bool shuffle;
  final String? title;
  final String? artists;
  final String? album;

  /// URL of the album cover.
  final String? cover;
  final int progressMs;
  final int durationMs;
}

class SpotifyItem {
  const SpotifyItem({required this.uri, required this.name, this.subtitle, this.image});

  /// "spotify:playlist:…" or "spotify:track:…".
  final String uri;
  final String name;
  final String? subtitle;
  final String? image;

  bool get isTrack => uri.startsWith('spotify:track:');
}

String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// The smallest image at least [min] px wide, else the largest one.
String? _image(Object? images, {int min = 64}) {
  if (images is! List || images.isEmpty) return null;
  final sorted = [
    for (final i in images)
      if (i is Map && _string(i['url']) != null) i,
  ]..sort((a, b) => ((a['width'] as num?) ?? 0).compareTo((b['width'] as num?) ?? 0));
  if (sorted.isEmpty) return null;
  for (final i in sorted) {
    if (((i['width'] as num?) ?? 0) >= min) return i['url'] as String;
  }
  return sorted.last['url'] as String;
}

SpotifyDevice? parseDevice(Object? d) {
  if (d is! Map) return null;
  final id = _string(d['id']);
  final name = _string(d['name']);
  if (id == null || name == null) return null;
  final volume = d['volume_percent'];
  return SpotifyDevice(
    id: id,
    name: name,
    type: _string(d['type']) ?? '',
    active: d['is_active'] == true,
    volume: d['supports_volume'] == false || volume is! num ? null : volume.round(),
  );
}

/// Reads `GET /me/player`; null for "nothing playing anywhere" (204).
SpotifyPlayback? parsePlayback(Object? json) {
  if (json is! Map) return null;
  final item = json['item'];
  String? title, artists, album, cover;
  var duration = 0;
  if (item is Map) {
    title = _string(item['name']);
    final list = item['artists'];
    if (list is List) {
      final names = [
        for (final a in list)
          if (a is Map) ?_string(a['name']),
      ];
      if (names.isNotEmpty) artists = names.join(', ');
    }
    final a = item['album'];
    if (a is Map) {
      album = _string(a['name']);
      cover = _image(a['images'], min: 150);
    }
    // Podcast episodes: show and its picture.
    final show = item['show'];
    if (show is Map) {
      artists ??= _string(show['name']);
      cover ??= _image(item['images'] ?? show['images'], min: 150);
    }
    final d = item['duration_ms'];
    if (d is num) duration = d.round();
  }
  final progress = json['progress_ms'];
  return SpotifyPlayback(
    device: parseDevice(json['device']),
    playing: json['is_playing'] == true,
    shuffle: json['shuffle_state'] == true,
    title: title,
    artists: artists,
    album: album,
    cover: cover,
    progressMs: progress is num ? progress.round() : 0,
    durationMs: duration,
  );
}

/// Reads `GET /me/player/devices`.
List<SpotifyDevice> parseDevices(Object? json) {
  final list = json is Map ? json['devices'] : null;
  return [
    if (list is List)
      for (final d in list) ?parseDevice(d),
  ];
}

/// Reads `GET /me/playlists`.
List<SpotifyItem> parsePlaylists(Object? json) {
  final items = json is Map ? json['items'] : null;
  final playlists = <SpotifyItem>[];
  if (items is! List) return playlists;
  for (final p in items) {
    if (p is! Map) continue;
    final uri = _string(p['uri']);
    final name = _string(p['name']);
    if (uri == null || name == null) continue;
    final tracks = p['tracks'];
    final total = tracks is Map ? tracks['total'] : null;
    playlists.add(
      SpotifyItem(
        uri: uri,
        name: name,
        subtitle: total is int ? '$total titres' : null,
        image: _image(p['images']),
      ),
    );
  }
  return playlists;
}

/// Reads `GET /search?type=track,playlist`: tracks first.
List<SpotifyItem> parseSearch(Object? json) {
  if (json is! Map) return const [];
  final results = <SpotifyItem>[];
  final tracks = json['tracks'];
  final trackItems = tracks is Map ? tracks['items'] : null;
  if (trackItems is List) {
    for (final t in trackItems) {
      if (t is! Map) continue;
      final uri = _string(t['uri']);
      final name = _string(t['name']);
      if (uri == null || name == null) continue;
      final artists = t['artists'];
      final album = t['album'];
      results.add(
        SpotifyItem(
          uri: uri,
          name: name,
          subtitle: artists is List
              ? [
                  for (final a in artists)
                    if (a is Map) ?_string(a['name']),
                ].join(', ')
              : null,
          image: album is Map ? _image(album['images']) : null,
        ),
      );
    }
  }
  final playlists = json['playlists'];
  results.addAll(parsePlaylists(playlists));
  return results;
}

/// "2:05".
String minutesSeconds(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
