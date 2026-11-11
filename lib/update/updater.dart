import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Build number of this copy of Nox, set by the CI
/// (`--dart-define=NOX_BUILD=<run number>`). 0 for a local build, which
/// never updates itself.
const kNoxBuild = int.fromEnvironment('NOX_BUILD');

const _latestRelease = 'https://api.github.com/repos/antoine28boel/nox/releases/latest';
const _downloadPrefix = 'https://github.com/antoine28boel/nox/releases/download/';
const _assetName = 'nox-windows.zip';

/// A newer build of Nox published by the CI.
class UpdateInfo {
  const UpdateInfo({required this.build, required this.url, this.sha256});

  final int build;
  final Uri url;

  /// Expected SHA-256 of the zip (lowercase hex), when GitHub provides it.
  final String? sha256;
}

/// Reads GitHub's "latest release" JSON. Returns the update it describes, or
/// null if it is not newer than [current] or is not a release of ours.
UpdateInfo? parseRelease(Object? json, int current) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final match = RegExp(r'^build-(\d+)$').firstMatch(tag);
  if (match == null) return null;
  final build = int.parse(match.group(1)!);
  if (build <= current) return null;

  final assets = json['assets'];
  if (assets is! List) return null;
  for (final asset in assets) {
    if (asset is! Map || asset['name'] != _assetName) continue;
    final url = asset['browser_download_url'];
    // Only ever download from our own releases, over HTTPS.
    if (url is! String || !url.startsWith(_downloadPrefix)) return null;
    final digest = asset['digest'];
    final sha = digest is String && digest.startsWith('sha256:')
        ? digest.substring(7).toLowerCase()
        : null;
    return UpdateInfo(build: build, url: Uri.parse(url), sha256: sha);
  }
  return null;
}

/// Extracts the hash from the output of `certutil -hashfile <file> SHA256`.
String? parseCertutilHash(String output) {
  for (final line in const LineSplitter().convert(output)) {
    final hex = line.replaceAll(' ', '').trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex;
  }
  return null;
}

/// Asks GitHub whether a newer build exists. Null if not, or on any error
/// (offline, rate limit…): Nox must keep working without the network.
Future<UpdateInfo?> checkForUpdate() async {
  if (kNoxBuild <= 0) return null;
  final client = HttpClient()..userAgent = 'nox-updater';
  try {
    final request =
        await client.getUrl(Uri.parse(_latestRelease)).timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final body =
        await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    return parseRelease(jsonDecode(body), kNoxBuild);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

// Waits for Nox to exit, replaces his files, then starts him again. If
// anything goes wrong the old files are left alone and Nox is restarted.
const _script = r'''
param([int]$ProcId, [string]$Zip, [string]$Dest, [string]$Exe)
$ErrorActionPreference = 'Stop'
try {
  try { Wait-Process -Id $ProcId -Timeout 30 } catch {}
  Start-Sleep -Milliseconds 500
  $new = Join-Path (Split-Path -Parent $Zip) 'new'
  Expand-Archive -LiteralPath $Zip -DestinationPath $new -Force
  if (Test-Path -LiteralPath (Join-Path $new 'nox.exe')) {
    Copy-Item -Path (Join-Path $new '*') -Destination $Dest -Recurse -Force
  }
} catch {
} finally {
  Start-Process -FilePath $Exe -WorkingDirectory $Dest
}
''';

/// Downloads [update], checks it, and starts the script that will replace
/// Nox's files once he has quit. Returns true when the caller must now quit.
Future<bool> downloadAndInstall(UpdateInfo update) async {
  final client = HttpClient()..userAgent = 'nox-updater';
  try {
    final dir = await Directory.systemTemp.createTemp('nox_update_');
    final zip = File('${dir.path}${Platform.pathSeparator}$_assetName');

    final request = await client.getUrl(update.url).timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return false;
    }
    await response.pipe(zip.openWrite()).timeout(const Duration(minutes: 10));

    final expected = update.sha256;
    if (expected != null) {
      final result = await Process.run('certutil', ['-hashfile', zip.path, 'SHA256']);
      if (parseCertutilHash('${result.stdout}') != expected) return false;
    }

    final script = File('${dir.path}${Platform.pathSeparator}update.ps1');
    await script.writeAsString(_script);
    final exe = Platform.resolvedExecutable;
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '$pid',
        zip.path,
        File(exe).parent.path,
        exe,
      ],
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
