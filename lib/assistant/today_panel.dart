import 'package:flutter/material.dart';

import 'brief.dart';
import 'ha_client.dart';
import 'panel_style.dart';
import 'panel_tabs.dart';
import 'today.dart';

/// Size of the panel window, in logical pixels.
const kPanelSize = Size(420, 600);

const _background = panelBackground;
const _text = panelText;
const _muted = panelMuted;
const _accent = panelAccent;

/// The assistant panel, in tabs: the day (brief, weather, agenda, tasks),
/// music, home devices, the week's agenda and the to-do lists, all from
/// Home Assistant; plus the form to connect to it.
class TodayPanel extends StatefulWidget {
  const TodayPanel({
    super.key,
    required this.now,
    required this.data,
    this.brief,
    required this.status,
    required this.configured,
    required this.haUrl,
    this.client,
    required this.onRefresh,
    required this.onClose,
    required this.onSaveSettings,
  });

  final DateTime now;

  /// Last data fetched (possibly from the offline cache), or null.
  final TodayData? data;

  /// Today's brief, if Nox has brought one.
  final Brief? brief;

  /// One line about freshness: "À jour à 09:12", "Hors ligne…".
  final String status;

  /// Whether a Home Assistant address and token are saved.
  final bool configured;
  final String haUrl;

  /// Connection to Home Assistant, when configured.
  final HaClient? client;

  final VoidCallback onRefresh;
  final VoidCallback onClose;

  /// Saves the address and token (an empty token keeps the saved one).
  /// Returns an error message, or null when the connection works.
  final Future<String?> Function(String url, String token) onSaveSettings;

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<TodayPanel> {
  late bool _settings = !widget.configured;
  late final _url = TextEditingController(text: widget.haUrl);
  final _token = TextEditingController();
  bool _saving = false;
  String? _error;

  /// Bumped by "Actualiser": rebuilds the live tabs, which reload.
  int _reload = 0;

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
    });
    final error = await widget.onSaveSettings(_url.text, _token.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) {
        _token.clear();
        _settings = false;
      }
    });
  }

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
                Expanded(child: _settings ? _settingsForm() : _tabs()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_settings ? 'Home Assistant' : 'Nox',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text(frenchDate(widget.now), style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          if (!_settings && widget.configured)
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
        tab(Icons.wb_sunny_outlined, 'Jour'),
        tab(Icons.music_note_rounded, 'Musique'),
        tab(Icons.home_outlined, 'Maison'),
        tab(Icons.calendar_month_outlined, 'Agenda'),
        tab(Icons.checklist_rounded, 'Tâches'),
      ],
    );
  }

  Widget _tabs() {
    final client = widget.client;
    Widget live(Widget Function(HaClient client) build) => client == null
        ? const Padding(
            padding: EdgeInsets.all(18),
            child: PanelNote('Nox n\'est pas encore relié à Home Assistant. Ouvre « Réglages ».'),
          )
        : KeyedSubtree(key: ValueKey(_reload), child: build(client));
    return TabBarView(
      children: [
        _today(),
        live((c) => MusicTab(client: c)),
        live((c) => HomeTab(client: c)),
        live((c) => AgendaTab(client: c, now: widget.now)),
        live((c) => TasksTab(client: c)),
      ],
    );
  }

  Widget _today() {
    final data = widget.data;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(widget.status, style: const TextStyle(color: _muted, fontSize: 12)),
        ),
        if (widget.brief case final brief?)
          PanelSection(title: 'Brief', children: [
            Text(brief.text, style: const TextStyle(height: 1.4)),
            if (brief.byAi)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Rédigé par l\'IA de Home Assistant',
                    style: TextStyle(color: _muted, fontSize: 11)),
              ),
          ]),
        if (!widget.configured)
          const PanelSection(title: 'Connexion', children: [
            Text('Nox n\'est pas encore relié à Home Assistant. Ouvre « Réglages ».'),
          ])
        else if (data == null)
          const PanelSection(title: 'En attente', children: [
            Text('Aucune donnée pour l\'instant.'),
          ])
        else ...[
          if (data.weather != null)
            PanelSection(title: 'Météo', children: [Text(weatherLabel(data.weather!))]),
          PanelSection(title: 'Agenda', children: [
            if (data.events.isEmpty) const Text('Rien de prévu.', style: TextStyle(color: _muted)),
            for (final e in data.events) _EventRow(event: e),
          ]),
          PanelSection(title: 'Tâches', children: [
            if (data.tasks.isEmpty)
              const Text('Aucune tâche en attente.', style: TextStyle(color: _muted)),
            for (final t in data.tasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('•  $t'),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _settingsForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      children: [
        const Text(
          'Adresse de ton Home Assistant et jeton d\'accès longue durée '
          '(profil utilisateur → Sécurité → Jetons d\'accès longue durée). '
          'Le jeton reste sur ce PC.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _url,
          enabled: !_saving,
          decoration: const InputDecoration(
              labelText: 'Adresse', hintText: 'https://ha.exemple.fr'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _token,
          enabled: !_saving,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Jeton',
            hintText: widget.configured ? 'Laisser vide pour garder le jeton actuel' : null,
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: panelError)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Test en cours…' : 'Tester et enregistrer'),
          ),
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

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AgendaEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(eventTime(event), style: const TextStyle(color: _muted)),
          ),
          Expanded(child: Text(event.title)),
        ],
      ),
    );
  }
}
