import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'nox/brain.dart';
import 'nox/nox_view.dart';
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
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setResizable(false);
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    await windowManager.show();
  });

  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('mode') == 'espiegle' ? NoxMode.espiegle : NoxMode.sage;

  launchAtStartup.setup(appName: 'Nox', appPath: Platform.resolvedExecutable);

  final desktop = WinDesktop(WinDesktop.findOwnWindow());
  final brain = NoxBrain(mode: mode)..scale = desktop.scale();
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

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _initTray();
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
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'title', label: 'Nox', disabled: true),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'sage', label: 'Mode sage', checked: mode == NoxMode.sage),
      MenuItem.checkbox(
          key: 'espiegle', label: 'Mode espiègle', checked: mode == NoxMode.espiegle),
      MenuItem.separator(),
      MenuItem(key: 'recall', label: 'Rappeler Nox'),
      MenuItem.checkbox(
          key: 'startup', label: 'Lancer au démarrage de Windows', checked: _startup),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quitter'),
    ]));
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
      case 'quit':
        await trayManager.destroy();
        await windowManager.destroy();
        exit(0);
    }
  }

  @override
  void dispose() {
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
          onMouseOver: (over) => windowManager.setIgnoreMouseEvents(!over),
        ),
      ),
    );
  }
}
