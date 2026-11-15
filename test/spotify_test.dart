import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/spotify.dart';

void main() {
  test('PKCE: verifier and challenge (RFC 7636 example)', () {
    final v = pkceVerifier(Random(1));
    expect(v, hasLength(64));
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    expect(
      pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('authorize address', () {
    final uri = spotifyAuthorizeUri('abc', 'xyz', 's1');
    expect(uri.host, 'accounts.spotify.com');
    expect(uri.queryParameters['redirect_uri'], kSpotifyRedirect);
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['scope'], contains('user-modify-playback-state'));
  });

  test('playback', () {
    final p = parsePlayback({
      'device': {
        'id': 'd1',
        'name': 'Bureau',
        'type': 'Computer',
        'is_active': true,
        'volume_percent': 42,
        'supports_volume': true,
      },
      'is_playing': true,
      'shuffle_state': false,
      'progress_ms': 65000,
      'item': {
        'name': 'Clair de lune',
        'duration_ms': 300000,
        'artists': [
          {'name': 'Debussy'},
          {'name': 'Kocsis'},
        ],
        'album': {
          'name': 'Suite bergamasque',
          'images': [
            {'url': 'big', 'width': 640},
            {'url': 'mid', 'width': 300},
            {'url': 'small', 'width': 64},
          ],
        },
      },
    })!;
    expect(p.title, 'Clair de lune');
    expect(p.artists, 'Debussy, Kocsis');
    expect(p.cover, 'mid');
    expect(p.device!.volume, 42);
    expect(p.playing, isTrue);
    expect(minutesSeconds(p.progressMs), '1:05');
    expect(parsePlayback(null), isNull);
  });

  test('devices, playlists and search', () {
    final devices = parseDevices({
      'devices': [
        {
          'id': 'a',
          'name': 'Salon',
          'type': 'Speaker',
          'supports_volume': false,
          'volume_percent': 10,
        },
        {'id': null, 'name': 'Restreint'},
      ],
    });
    expect(devices.single.name, 'Salon');
    expect(devices.single.volume, isNull);

    final playlists = parsePlaylists({
      'items': [
        {
          'uri': 'spotify:playlist:1',
          'name': 'Matin',
          'tracks': {'total': 12},
          'images': null,
        },
        null,
      ],
    });
    expect(playlists.single.subtitle, '12 titres');
    expect(playlists.single.isTrack, isFalse);

    final results = parseSearch({
      'tracks': {
        'items': [
          {
            'uri': 'spotify:track:9',
            'name': 'Gymnopédie',
            'artists': [
              {'name': 'Satie'},
            ],
          },
        ],
      },
      'playlists': {
        'items': [
          {'uri': 'spotify:playlist:2', 'name': 'Calme'},
        ],
      },
    });
    expect(results.map((r) => r.name), ['Gymnopédie', 'Calme']);
    expect(results.first.subtitle, 'Satie');
    expect(results.first.isTrack, isTrue);
  });
}
