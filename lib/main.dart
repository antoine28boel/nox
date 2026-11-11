import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'nox/brain.dart';
import 'nox/feather.dart';
import 'nox/nox_view.dart';
import 'update/updater.dart';
import 'win/win_desktop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  const options = WindowOptions(
    size: kNoxWindowSize,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Nox',
  );
  final desktop = WinDesktop(WinDesktop.findOwnWindow());
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setResizable(false);
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    desktop.makeLayered();
    desktop.setClickThrough(true);
    // Inactive: Nox must not take the focus from the app in use.
    await windowManager.show(inactive: true);
  });

  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('mode') == 'espiegle' ? NoxMode.espiegle : NoxMode.sage;

  launchAtStartup.setup(appName: 'Nox', appPath: Platform.resolvedExecutable);

  final pranks = {
    for (final prank in NoxPrank.values)
      if (prefs.getBool('prank_${prank.name}') ?? true) prank,
  };

  final brain = NoxBrain(mode: mode, pranks: pranks)..scale = desktop.scale();
  final feather = renderFeather(desktop.scale());
  desktop.setFeatherImage(feather.bgra, feather.width, feather.height);
  brain.spawn(desktop, desktop.cursor());

  runApp(NoxApp(brain: brain, desktop: desktop, prefs: prefs));
}

class NoxApp extends StatefulWidget {
  const NoxApp({super.key, required this.brain, required this.desktop, required this.prefs});

  final NoxBrain brain;
  final WinDesktop desktop;
  final SharedPreferences prefs;

  @override
  State<NoxApp> createState() => _NoxAppState();
}

class _NoxAppState extends State<NoxApp> with TrayListener {
  bool _startup = false;

  /// An update Nox is offering, waiting for a yes or a no.
  UpdateInfo? _update;
  bool _installing = false;
  Timer? _firstCheck;
  Timer? _dailyCheck;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _initTray();
    _firstCheck = Timer(const Duration(seconds: 20), _checkForUpdate);
    _dailyCheck = Timer.periodic(const Duration(hours: 24), (_) => _checkForUpdate());
  }

  /// Looks for a newer build; if there is one, Nox brings it as news.
  /// [manual] also re-offers a build that was declined before.
  Future<void> _checkForUpdate({bool manual = false}) async {
    if (_installing) return;
    final update = await checkForUpdate();
    if (!mounted) return;
    final declined = widget.prefs.getInt('update_declined') ?? 0;
    if (update == null || (!manual && update.build <= declined)) return;
    _update = update;
    widget.brain.carrying = true;
    await _refreshMenu();
  }

  Future<void> _answerUpdate(bool accept) async {
    final update = _update;
    if (update == null || _installing) return;
    if (!accept) {
      _update = null;
      widget.brain.carrying = false;
      await widget.prefs.setInt('update_declined', update.build);
      await _refreshMenu();
      return;
    }
    _installing = true;
    await _refreshMenu();
    if (await downloadAndInstall(update)) {
      await _quit();
    }
    // The download failed: keep the offer so it can be tried again.
    _installing = false;
    await _refreshMenu();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  Future<void> _initTray() async {
    try {
      _startup = await launchAtStartup.isEnabled();
    } catch (_) {
      _startup = false;
    }
    await trayManager.setIcon('assets/nox.ico');
    await trayManager.setToolTip('Nox veille');
    await _refreshMenu();
  }

  Future<void> _refreshMenu() async {
    final mode = widget.brain.mode;
    final update = _update;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'title', label: 'Nox', disabled: true),
      MenuItem.separator(),
      if (update != null) ...[
        MenuItem(
            key: 'update_title',
            label: _installing
                ? 'Mise à jour en cours…'
                : 'Nox apporte une mise à jour (version ${update.build})',
            disabled: true),
        if (!_installing) MenuItem(key: 'update_accept', label: 'Accepter'),
        if (!_installing) MenuItem(key: 'update_decline', label: 'Refuser'),
        MenuItem.separator(),
      ],
      MenuItem.checkbox(key: 'sage', label: 'Mode sage', checked: mode == NoxMode.sage),
      MenuItem.checkbox(
          key: 'espiegle', label: 'Mode espiègle', checked: mode == NoxMode.espiegle),
      MenuItem.separator(),
      MenuItem(key: 'pranks', label: 'Bêtises (mode espiègle)', disabled: true),
      for (final prank in NoxPrank.values)
        MenuItem.checkbox(
            key: 'prank_${prank.name}',
            label: _prankLabels[prank]!,
            checked: widget.brain.pranks.contains(prank)),
      MenuItem.separator(),
      MenuItem(key: 'recall', label: 'Rappeler Nox'),
      MenuItem.checkbox(
          key: 'startup', label: 'Lancer au démarrage de Windows', checked: _startup),
      if (update == null)
        MenuItem(key: 'update_check', label: 'Rechercher une mise à jour'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quitter'),
    ]));
  }

  static const _prankLabels = {
    NoxPrank.chase: 'Chasser le curseur',
    NoxPrank.feather: 'Laisser une plume',
    NoxPrank.peck: 'Picorer une icône',
    NoxPrank.push: 'Pousser la fenêtre',
  };

  Future<void> _togglePrank(NoxPrank prank) async {
    final pranks = widget.brain.pranks;
    final on = !pranks.contains(prank);
    on ? pranks.add(prank) : pranks.remove(prank);
    await widget.prefs.setBool('prank_${prank.name}', on);
    await _refreshMenu();
  }

  Future<void> _setMode(NoxMode mode) async {
    widget.brain.mode = mode;
    await widget.prefs.setString('mode', mode.name);
    await _refreshMenu();
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    for (final prank in NoxPrank.values) {
      if (menuItem.key == 'prank_${prank.name}') {
        await _togglePrank(prank);
        return;
      }
    }
    switch (menuItem.key) {
      case 'sage':
        await _setMode(NoxMode.sage);
      case 'espiegle':
        await _setMode(NoxMode.espiegle);
      case 'recall':
        widget.brain.recall(widget.desktop, widget.desktop.cursor());
      case 'startup':
        _startup ? await launchAtStartup.disable() : await launchAtStartup.enable();
        _startup = await launchAtStartup.isEnabled();
        await _refreshMenu();
      case 'update_accept':
        await _answerUpdate(true);
      case 'update_decline':
        await _answerUpdate(false);
      case 'update_check':
        await _checkForUpdate(manual: true);
      case 'quit':
        await _quit();
    }
  }

  @override
  void dispose() {
    _firstCheck?.cancel();
    _dailyCheck?.cancel();
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: NoxView(
          brain: widget.brain,
          desktop: widget.desktop,
          onMouseOver: (over) => widget.desktop.setClickThrough(!over),
        ),
      ),
    );
  }
}
