import 'package:flutter/material.dart';

import 'brief.dart';
import 'today.dart';

/// Size of the panel window, in logical pixels.
const kPanelSize = Size(380, 540);

const _background = Color(0xFF2B211A);
const _card = Color(0xFF3A2D23);
const _text = Color(0xFFF5E9D3);
const _muted = Color(0xFFBFAE95);
const _accent = Color(0xFFF2B53A);

/// The "Aujourd'hui" panel: weather, agenda and tasks read from Home
/// Assistant, plus the form to connect to it.
class TodayPanel extends StatefulWidget {
  const TodayPanel({
    super.key,
    required this.now,
    required this.data,
    this.brief,
    required this.status,
    required this.configured,
    required this.haUrl,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(child: _settings ? _settingsForm() : _today()),
            ],
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
                Text(_settings ? 'Home Assistant' : "Aujourd'hui",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text(frenchDate(widget.now), style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          if (!_settings && widget.configured)
            _HeaderButton(label: 'Actualiser', onTap: widget.onRefresh),
          _HeaderButton(
            label: _settings ? 'Retour' : 'Réglages',
            onTap: () => setState(() => _settings = !_settings),
          ),
          _HeaderButton(label: 'Fermer', onTap: widget.onClose),
        ],
      ),
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
          _Section(title: 'Brief', children: [
            Text(brief.text, style: const TextStyle(height: 1.4)),
            if (brief.byAi)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Rédigé par l\'IA de Home Assistant',
                    style: TextStyle(color: _muted, fontSize: 11)),
              ),
          ]),
        if (!widget.configured)
          const _Section(title: 'Connexion', children: [
            Text('Nox n\'est pas encore relié à Home Assistant. Ouvre « Réglages ».'),
          ])
        else if (data == null)
          const _Section(title: 'En attente', children: [
            Text('Aucune donnée pour l\'instant.'),
          ])
        else ...[
          if (data.weather != null)
            _Section(title: 'Météo', children: [Text(weatherLabel(data.weather!))]),
          _Section(title: 'Agenda', children: [
            if (data.events.isEmpty) const Text('Rien de prévu.', style: TextStyle(color: _muted)),
            for (final e in data.events) _EventRow(event: e),
          ]),
          _Section(title: 'Tâches', children: [
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
            child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8F8F))),
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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      child: Text(label),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title.toUpperCase(),
                style: const TextStyle(
                    color: _accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          ...children,
        ],
      ),
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
