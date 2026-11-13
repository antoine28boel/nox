import 'package:flutter_test/flutter_test.dart';
import 'package:nox/update/updater.dart';

Map<String, Object?> release({
  String tag = 'build-12',
  String name = 'nox-windows.zip',
  String url = 'https://github.com/antoine28boel/nox/releases/download/build-12/nox-windows.zip',
  String? digest,
}) =>
    {
      'tag_name': tag,
      'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'https://example.com/notes.txt'},
        {'name': name, 'browser_download_url': url, 'digest': digest},
      ],
    };

void main() {
  group('parseRelease', () {
    test('offers a newer build', () {
      final u = parseRelease(release(digest: 'sha256:ABCDEF'), 11)!;
      expect(u.build, 12);
      expect(u.url.path, endsWith('/build-12/nox-windows.zip'));
      expect(u.sha256, 'abcdef');
    });

    test('ignores the same or an older build', () {
      expect(parseRelease(release(), 12), isNull);
      expect(parseRelease(release(), 40), isNull);
    });

    test('works without a digest', () {
      expect(parseRelease(release(), 1)!.sha256, isNull);
    });

    test('refuses a download from anywhere else', () {
      expect(parseRelease(release(url: 'https://example.com/nox-windows.zip'), 1), isNull);
      expect(
          parseRelease(
              release(url: 'http://github.com/antoine28boel/nox/releases/download/x.zip'), 1),
          isNull);
    });

    test('ignores anything that is not one of our releases', () {
      expect(parseRelease(release(tag: 'v1.0'), 1), isNull);
      expect(parseRelease(release(name: 'other.zip'), 1), isNull);
      expect(parseRelease({'tag_name': 'build-12'}, 1), isNull);
      expect(parseRelease('nope', 1), isNull);
      expect(parseRelease(null, 1), isNull);
    });
  });

  group('parseCertutilHash', () {
    const hash = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

    test('reads the hash line', () {
      const out = 'SHA256 hash of C:\\tmp\\nox-windows.zip:\r\n$hash\r\n'
          'CertUtil: -hashfile command completed successfully.\r\n';
      expect(parseCertutilHash(out), hash);
    });

    test('accepts spaced, upper-case output', () {
      final spaced = hash.toUpperCase().replaceAllMapped(RegExp('..'), (m) => '${m[0]} ');
      expect(parseCertutilHash('header\n$spaced\nfooter'), hash);
    });

    test('returns null when there is no hash', () {
      expect(parseCertutilHash('CertUtil: -hashfile command FAILED'), isNull);
    });
  });

  group('parseInstallArgs', () {
    test('reads the installer command line', () {
      final r = parseInstallArgs(['--nox-install', r'C:\Nox', '4242'])!;
      expect(r.target, r'C:\Nox');
      expect(r.oldPid, 4242);
    });

    test('a normal start is not an install', () {
      expect(parseInstallArgs([]), isNull);
      expect(parseInstallArgs(['--nox-install', r'C:\Nox']), isNull);
      expect(parseInstallArgs(['--nox-install', r'C:\Nox', 'abc']), isNull);
      expect(parseInstallArgs(['--other', r'C:\Nox', '1']), isNull);
    });
  });

  test('copyOrder copies nox.exe last', () {
    expect(
      copyOrder(['nox.exe', r'data\app.so', 'flutter_windows.dll', r'data\icudtl.dat']),
      [r'data\app.so', r'data\icudtl.dat', 'flutter_windows.dll', 'nox.exe'],
    );
  });
}
