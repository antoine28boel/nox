import 'package:flutter/material.dart';

import 'brief.dart';
import 'ha_client.dart';
import 'panel_style.dart';
import 'panel_tabs.dart';
import 'spotify.dart';
import 'spotify_client.dart';
import 'today.dart';
import 'vikunja_client.dart';

/// Size of the panel window, in logical pixels.
const kPanelSize = Size(420, 600);

const _background = panelBackground;
const _text = panelText;
const _muted = panelMuted;
const _accent = panelAccent;

/// Saves an address and a token (an empty token keeps the saved one).
/// Returns an error message, or null when the connection works.
typedef SaveServer = Future<String?> Function(String url, String token);

/// The assistant panel, in tabs: project tracking (Vikunja), music, home
/// devices, the week's agenda and the to-do lists (Home Assistant); plus
/// the forms to connect to both.
class TodayPanel extends StatefulWidget {
  const TodayPanel({
    super.key,
    required this.now,
    required this.data,
    this.brief,
    required this.configured,
    required this.haUrl,
    this.client,
    this.vikunjaUrl = '',
    this.vikunja,
    this.spotify,
    this.spotifyClientId = '',
    required this.onSpotifyLogin,
    required this.onSpotifyLogout,
    required this.onRefresh,
    required this.onClose,
    required this.onSaveSettings,
    required this.onSaveVikunja,
  });

  final DateTime now;

  /// Last data fetched (possibly from the offline cache), or null.
  final TodayData? data;

  /// Today's brief, if Nox has brought one.
  final Brief? brief;

  /// Whether a Home Assistant address and token are saved.
  final bool configured;
  final String haUrl;

  /// Connection to Home Assistant, when configured.
  final HaClient? client;

  final String vikunjaUrl;

  /// Connection to Vikunja, when configured.
  final VikunjaClient? vikunja;

  /// Connection to Spotify, when logged in.
  final SpotifyClient? spotify;
  final String spotifyClientId;

  /// Logs in to Spotify with this Client ID; returns an error message or null.
  final Future<String?> Function(String clientId) onSpotifyLogin;
  final VoidCallback onSpotifyLogout;

  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final SaveServer onSaveSettings;
  final SaveServer onSaveVikunja;

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<TodayPanel> {
  late bool _settings = !widget.configured && widget.vikunja == null && widget.spotify == null;

  /// Bumped by "Actualiser": rebuilds the live tabs, which reload.
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: _background,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: DefaultTextStyle(
          style: const TextStyle(color: _text, fontSize: 14),
          child: DefaultTabController(
            length: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                if (!_settings) _tabBar(),
                Expanded(child: _settings ? _settingsForms() : _tabs()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final weather = widget.data?.weather;
    final subtitle = [
      frenchDate(widget.now),
      if (!_settings && weather != null && isFromToday(widget.data!, widget.now))
        weatherLabel(weather),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _settings ? 'Réglages' : 'Nox',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
          if (!_settings)
            _HeaderButton(
              label: 'Actualiser',
              onTap: () {
                setState(() => _reload++);
                widget.onRefresh();
              },
            ),
          _HeaderButton(
            label: _settings ? 'Retour' : 'Réglages',
            onTap: () => setState(() => _settings = !_settings),
          ),
          _HeaderButton(label: 'Fermer', onTap: widget.onClose),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Tab tab(IconData icon, String label) => Tab(
      height: 50,
      iconMargin: const EdgeInsets.only(bottom: 2),
      icon: Icon(icon, size: 20),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
    return TabBar(
      labelColor: _accent,
      unselectedLabelColor: _muted,
      indicatorColor: _accent,
      dividerColor: Colors.transparent,
      labelPadding: EdgeInsets.zero,
      tabs: [
        tab(Icons.track_changes_rounded, 'Suivi'),
        tab(Icons.music_note_rounded, 'Musique'),
        tab(Icons.home_outlined, 'Maison'),
        tab(Icons.calendar_month_outlined, 'Agenda'),
        tab(Icons.checklist_rounded, 'Tâches'),
      ],
    );
  }

  Widget _tabs() {
    Widget missing(String what) => Padding(
      padding: const EdgeInsets.all(18),
      child: PanelNote('Nox n\'est pas encore relié à $what. Ouvre « Réglages ».'),
    );
    Widget keyed(Widget child) => KeyedSubtree(key: ValueKey(_reload), child: child);
    final client = widget.client;
    Widget live(Widget Function(HaClient client) build) =>
        client == null ? missing('Home Assistant') : keyed(build(client));
    final vikunja = widget.vikunja;
    return TabBarView(
      children: [
        vikunja == null ? missing('Vikunja') : keyed(TrackingTab(client: vikunja)),
        client == null && widget.spotify == null
            ? missing('Home Assistant ni à Spotify')
            : keyed(MusicTab(client: client, spotify: widget.spotify)),
        live((c) => HomeTab(client: c)),
        live((c) => AgendaTab(client: c, now: widget.now, brief: widget.brief)),
        live((c) => TasksTab(client: c)),
      ],
    );
  }

  Widget _settingsForms() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      children: [
        _ServerForm(
          title: 'Home Assistant',
          intro:
              'Adresse de ton Home Assistant et jeton d\'accès longue durée '
              '(profil utilisateur → Sécurité → Jetons d\'accès longue durée). '
              'Le jeton reste sur ce PC.',
          url: widget.haUrl,
          hint: 'https://ha.exemple.fr',
          configured: widget.configured,
          onSave: widget.onSaveSettings,
        ),
        _ServerForm(
          title: 'Vikunja',
          intro:
              'Adresse de ton Vikunja et jeton d\'API (Paramètres → Jetons d\'API, '
              'droits de lecture sur les projets et les tâches). Les tâches d\'une '
              'colonne Kanban « En cours » ou avec l\'étiquette « En cours » sont '
              'suivies ; le projet « Claude » regroupe les tâches de Claude.',
          url: widget.vikunjaUrl,
          hint: 'http://vikunja.local:3456',
          configured: widget.vikunja != null,
          onSave: widget.onSaveVikunja,
        ),
        _SpotifyForm(
          clientId: widget.spotifyClientId,
          connected: widget.spotify != null,
          onLogin: widget.onSpotifyLogin,
          onLogout: widget.onSpotifyLogout,
        ),
      ],
    );
  }
}

/// Address and token of one server, with a "test and save" button.
class _ServerForm extends StatefulWidget {
  const _ServerForm({
    required this.title,
    required this.intro,
    required this.url,
    required this.hint,
    required this.configured,
    required this.onSave,
  });

  final String title;
  final String intro;
  final String url;
  final String hint;
  final bool configured;
  final SaveServer onSave;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  late final _url = TextEditingController(text: widget.url);
  final _token = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    final error = await widget.onSave(_url.text, _token.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      _saved = error == null;
      if (error == null) _token.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: widget.title,
      children: [
        Text(widget.intro, style: const TextStyle(color: _muted, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          enabled: !_saving,
          decoration: InputDecoration(labelText: 'Adresse', hintText: widget.hint),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _token,
          enabled: !_saving,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Jeton',
            hintText: widget.configured ? 'Laisser vide pour garder le jeton actuel' : null,
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: const TextStyle(color: panelError)),
          ),
        Row(
          children: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Test en cours…' : 'Tester et enregistrer'),
            ),
            if (_saved)
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Text('Connecté', style: TextStyle(color: _accent)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Client ID of the user's Spotify app and the login button.
class _SpotifyForm extends StatefulWidget {
  const _SpotifyForm({
    required this.clientId,
    required this.connected,
    required this.onLogin,
    required this.onLogout,
  });

  final String clientId;
  final bool connected;
  final Future<String?> Function(String clientId) onLogin;
  final VoidCallback onLogout;

  @override
  State<_SpotifyForm> createState() => _SpotifyFormState();
}

class _SpotifyFormState extends State<_SpotifyForm> {
  late final _clientId = TextEditingController(text: widget.clientId);
  bool _waiting = false;
  String? _error;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _waiting = true;
      _error = null;
    });
    final error = await widget.onLogin(_clientId.text.trim());
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: 'Spotify',
      children: [
        const SelectableText(
          'Crée une app gratuite sur developer.spotify.com/dashboard (API : Web API), '
          'ajoute l\'adresse de redirection $kSpotifyRedirect, puis colle son Client ID '
          'ici. La connexion s\'ouvre dans ton navigateur. Premium est nécessaire pour '
          'piloter la lecture.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clientId,
          enabled: !_waiting,
          decoration: const InputDecoration(labelText: 'Client ID'),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: const TextStyle(color: panelError)),
          ),
        Row(
          children: [
            FilledButton(
              onPressed: _waiting ? null : _login,
              child: Text(
                _waiting
                    ? 'En attente du navigateur…'
                    : widget.connected
                    ? 'Se reconnecter'
                    : 'Se connecter à Spotify',
              ),
            ),
            if (widget.connected && !_waiting) ...[
              const SizedBox(width: 6),
              TextButton(onPressed: widget.onLogout, child: const Text('Déconnecter')),
            ],
          ],
        ),
        if (widget.connected && !_waiting)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Connecté', style: TextStyle(color: _accent)),
          ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _accent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
