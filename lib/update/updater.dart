import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
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

// How an update is installed, without any script:
//  1. the running Nox downloads the zip, checks it and unpacks it into
//     %LOCALAPPDATA%\Nox\update\build-N;
//  2. he starts the new nox.exe from there with `--nox-install <dir> <pid>`
//     and quits;
//  3. that new Nox waits for the old one to be gone, copies itself over the
//     install folder (nox.exe last), starts the installed nox.exe and quits,
//     before showing any window;
//  4. the installed Nox deletes the unpacked copy.
// Every step is written to %LOCALAPPDATA%\Nox\update.log.

const _installFlag = '--nox-install';

/// What the copy started with `--nox-install` has to do.
class InstallRequest {
  const InstallRequest(this.target, this.oldPid);

  /// Folder of the Nox being replaced.
  final String target;
  final int oldPid;
}

/// Reads the command line of the unpacked new Nox. Null for a normal start.
InstallRequest? parseInstallArgs(List<String> args) {
  if (args.length != 3 || args[0] != _installFlag) return null;
  final pid = int.tryParse(args[2]);
  if (pid == null || args[1].isEmpty) return null;
  return InstallRequest(args[1], pid);
}

/// Paths of [files] (relative to the unpacked folder) in copy order:
/// nox.exe last, so a copy cut short leaves the old executable in place.
List<String> copyOrder(Iterable<String> files) {
  final list = [...files]..sort();
  final exe = list.where((f) => f.toLowerCase() == 'nox.exe').toList();
  list.removeWhere((f) => f.toLowerCase() == 'nox.exe');
  return [...list, ...exe];
}

String get _sep => Platform.pathSeparator;

String _noxDataDir() {
  final local = Platform.environment['LOCALAPPDATA'];
  final base = local != null && local.isNotEmpty ? local : Directory.systemTemp.path;
  return '$base${_sep}Nox';
}

String get _stagingRoot => '${_noxDataDir()}${_sep}update';

/// Where the steps of the last updates are written.
String get updateLogPath => '${_noxDataDir()}${_sep}update.log';

void updateLog(String message) {
  try {
    final file = File(updateLogPath);
    file.parent.createSync(recursive: true);
    // Keeps the journal small.
    if (file.existsSync() && file.lengthSync() > 200000) file.deleteSync();
    final at = DateTime.now().toIso8601String().substring(0, 19);
    file.writeAsStringSync('$at [$pid] $message\r\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Unpacks [zip] into [dest] with Windows' own tar, or PowerShell if that
/// fails. True when a nox.exe came out.
Future<bool> _unpack(File zip, Directory dest) async {
  final exe = File('${dest.path}${_sep}nox.exe');
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  // The full path: Git's tar, often first in PATH, cannot read zips.
  final tar = await Process.run('$root\\System32\\tar.exe', ['-xf', zip.path, '-C', dest.path]);
  updateLog('tar: code ${tar.exitCode} ${tar.stderr}'.trim());
  if (tar.exitCode == 0 && exe.existsSync()) return true;
  final ps = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "Expand-Archive -LiteralPath '${zip.path.replaceAll("'", "''")}' "
        "-DestinationPath '${dest.path.replaceAll("'", "''")}' -Force",
  ]);
  updateLog('Expand-Archive: code ${ps.exitCode} ${ps.stderr}'.trim());
  return exe.existsSync();
}

/// Downloads [update], checks and unpacks it, then starts the new Nox that
/// will replace this one. Returns null when the caller must now quit, or
/// what went wrong.
Future<String?> downloadAndInstall(UpdateInfo update) async {
  updateLog('Mise à jour ${update.build} acceptée (version actuelle $kNoxBuild).');
  final client = HttpClient()..userAgent = 'nox-updater';
  try {
    final dir = Directory('$_stagingRoot${_sep}build-${update.build}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final zip = File('$_stagingRoot${_sep}build-${update.build}.zip');

    final request = await client.getUrl(update.url).timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      updateLog('Téléchargement : HTTP ${response.statusCode}.');
      return 'Téléchargement refusé (${response.statusCode}).';
    }
    await response.pipe(zip.openWrite()).timeout(const Duration(minutes: 10));
    updateLog('Téléchargé : ${zip.lengthSync()} octets.');

    final expected = update.sha256;
    if (expected != null) {
      final result = await Process.run('certutil', ['-hashfile', zip.path, 'SHA256']);
      final actual = parseCertutilHash('${result.stdout}');
      if (actual != expected) {
        updateLog('Empreinte incorrecte : $actual au lieu de $expected.');
        return 'Fichier téléchargé corrompu.';
      }
      updateLog('Empreinte vérifiée.');
    }

    if (!await _unpack(zip, dir)) return 'Impossible de décompresser la mise à jour.';
    try {
      zip.deleteSync();
    } catch (_) {}

    final target = File(Platform.resolvedExecutable).parent.path;
    final staged = '${dir.path}${_sep}nox.exe';
    await Process.start(staged, [_installFlag, target, '$pid'],
        workingDirectory: dir.path, mode: ProcessStartMode.detached);
    updateLog('Lancé $staged pour installer dans $target.');
    return null;
  } catch (e) {
    updateLog('Échec : $e');
    return 'La mise à jour a échoué.';
  } finally {
    client.close(force: true);
  }
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openProcess = _kernel32
    .lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>(
        'OpenProcess');
final _waitForSingleObject =
    _kernel32.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject');
final _closeHandle =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

/// Waits until process [id] has exited (at most [timeout]).
void _waitForExit(int id, Duration timeout) {
  const synchronize = 0x00100000;
  final handle = _openProcess(synchronize, 0, id);
  if (handle == 0) return; // Already gone.
  try {
    _waitForSingleObject(handle, timeout.inMilliseconds);
  } finally {
    _closeHandle(handle);
  }
}

/// Run by the unpacked new Nox: replaces the old files, starts the
/// installed Nox. Never shows a window; the caller exits right after.
Future<void> finishInstall(InstallRequest request) async {
  final source = File(Platform.resolvedExecutable).parent;
  updateLog('Installation depuis ${source.path} vers ${request.target}.');
  _waitForExit(request.oldPid, const Duration(seconds: 30));

  final files = [
    for (final entity in source.listSync(recursive: true))
      if (entity is File) entity.path.substring(source.path.length + 1),
  ];
  var copied = false;
  // Files of the old Nox can stay locked a moment after he quits.
  for (var attempt = 1; attempt <= 20 && !copied; attempt++) {
    try {
      for (final rel in copyOrder(files)) {
        final dest = File('${request.target}$_sep$rel');
        dest.parent.createSync(recursive: true);
        File('${source.path}$_sep$rel').copySync(dest.path);
      }
      copied = true;
    } catch (e) {
      updateLog('Copie, essai $attempt : $e');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  updateLog(copied ? 'Fichiers remplacés.' : 'Échec de la copie : ancienne version conservée.');

  final exe = '${request.target}${_sep}nox.exe';
  try {
    await Process.start(exe, const [],
        workingDirectory: request.target, mode: ProcessStartMode.detached);
    updateLog('Redémarrage de $exe.');
  } catch (e) {
    updateLog('Impossible de relancer $exe : $e');
  }
}

/// Deletes what a finished update left behind (from the installed Nox).
void cleanUpdate() {
  final root = Directory(_stagingRoot);
  if (!root.existsSync()) return;
  if (Platform.resolvedExecutable.startsWith(root.path)) return;
  try {
    root.deleteSync(recursive: true);
    updateLog('Démarré en version $kNoxBuild ; copie temporaire supprimée.');
  } catch (_) {
    // Still locked by the installer finishing: next start.
  }
}
