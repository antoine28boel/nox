import 'dart:async';

import 'package:flutter/material.dart';

import 'ha_client.dart';
import 'home.dart';
import 'panel_style.dart';
import 'today.dart';

/// Shared behavior of the live tabs: loads from Home Assistant when shown,
/// again every [every] while visible, and after each action.
mixin _LiveTab<T extends StatefulWidget, D> on State<T> {
  HaClient get client;
  Duration? get every => null;

  D? data;
  String? error;
  bool loading = false;
  Timer? _timer;

  Future<D> load();

  @override
  void initState() {
    super.initState();
    refresh();
    final period = every;
    if (period != null) _timer = Timer.periodic(period, (_) => refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (loading) return;
    loading = true;
    if (!quiet) setState(() {});
    try {
      final result = await load();
      if (!mounted) return;
      setState(() {
        data = result;
        error = null;
      });
    } on HaException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Home Assistant injoignable');
    } finally {
      loading = false;
      if (mounted) setState(() {});
    }
  }

  /// Runs a service call, then reloads.
  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } on HaException catch (e) {
      if (mounted) setState(() => error = e.message);
      return;
    } catch (_) {
      if (mounted) setState(() => error = 'Home Assistant injoignable');
      return;
    }
    await refresh(quiet: true);
  }

  /// The common frame: error line, spinner on first load, then [content].
  Widget frame(List<Widget> Function(D data) content) {
    final d = data;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      children: [
        if (error != null) PanelNote(error!, error: true),
        if (d == null && loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (d != null)
          ...content(d),
      ],
    );
  }
}

// ---------------------------------------------------------------- Musique

class MusicTab extends StatefulWidget {
  const MusicTab({super.key, required this.client});

  final HaClient client;

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> with _LiveTab<MusicTab, List<MediaPlayer>> {
  @override
  HaClient get client => widget.client;
  @override
  Duration get every => const Duration(seconds: 3);

  /// Volume being dragged, per player, so polling does not fight the slider.
  final _dragging = <String, double>{};

  @override
  Future<List<MediaPlayer>> load() async => parseMediaPlayers(await client.states());

  Future<void> _call(MediaPlayer p, String service, [Map<String, Object?> extra = const {}]) =>
      act(() => client.callService('media_player', service, {'entity_id': p.id, ...extra}));

  @override
  Widget build(BuildContext context) {
    return frame((players) => [
          if (players.isEmpty) const PanelNote('Aucun lecteur trouvé dans Home Assistant.'),
          for (final p in players) _player(p),
        ]);
  }

  Widget _player(MediaPlayer p) {
    final picture = p.picture;
    final volume = _dragging[p.id] ?? p.volume;
    return PanelSection(
      title: p.name,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                color: panelBackground,
                child: picture != null && p.active
                    ? Image.network(
                        client.pictureUri(picture).toString(),
                        headers: {'Authorization': 'Bearer ${client.token}'},
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const Icon(Icons.music_note, color: panelMuted),
                      )
                    : const Icon(Icons.music_note, color: panelMuted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.active ? (p.title ?? 'Lecture en cours') : _idle(p.state),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (p.active && p.artist != null)
                    Text(p.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: panelMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Précédent',
              onPressed: p.active && p.canPrevious ? () => _call(p, 'media_previous_track') : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              tooltip: p.playing ? 'Pause' : 'Lecture',
              onPressed: p.state == 'off' ? null : () => _call(p, 'media_play_pause'),
              icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Suivant',
              onPressed: p.active && p.canNext ? () => _call(p, 'media_next_track') : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        if (p.canSetVolume && volume != null)
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, size: 18, color: panelMuted),
              Expanded(
                child: Slider(
                  value: volume.clamp(0.0, 1.0),
                  onChanged: (v) => setState(() => _dragging[p.id] = v),
                  onChangeEnd: (v) async {
                    await _call(p, 'volume_set', {'volume_level': double.parse(v.toStringAsFixed(2))});
                    if (mounted) setState(() => _dragging.remove(p.id));
                  },
                ),
              ),
              const Icon(Icons.volume_up_rounded, size: 18, color: panelMuted),
            ],
          ),
      ],
    );
  }

  String _idle(String state) =>
      const {'off': 'Éteint', 'idle': 'En attente', 'on': 'Allumé', 'standby': 'En veille'}[state] ??
      state;
}

// ---------------------------------------------------------------- Maison

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.client});

  final HaClient client;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with _LiveTab<HomeTab, Map<String, List<HomeDevice>>> {
  @override
  HaClient get client => widget.client;
  @override
  Duration get every => const Duration(seconds: 10);

  @override
  Future<Map<String, List<HomeDevice>>> load() async => parseHomeDevices(await client.states());

  Future<void> _call(HomeDevice d, String service, [Map<String, Object?> extra = const {}]) =>
      act(() => client.callService(d.domain, service, {'entity_id': d.id, ...extra}));

  @override
  Widget build(BuildContext context) {
    return frame((groups) => [
          if (groups.isEmpty) const PanelNote('Aucun appareil trouvé dans Home Assistant.'),
          for (final entry in groups.entries)
            PanelSection(
              title: homeDomainLabels[entry.key] ?? entry.key,
              children: [
                if (entry.key == 'scene' || entry.key == 'script')
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final d in entry.value)
                        ActionChip(
                          label: Text(d.name),
                          onPressed: d.available ? () => _call(d, 'turn_on') : null,
                        ),
                    ],
                  )
                else
                  for (final d in entry.value) _device(d),
              ],
            ),
        ]);
  }

  Widget _device(HomeDevice d) {
    final label = deviceLabel(d);
    Widget? control;
    if (d.toggles) {
      control = Switch(
        value: d.state == 'on',
        onChanged: d.available ? (v) => _call(d, v ? 'turn_on' : 'turn_off') : null,
      );
    } else if (d.domain == 'cover') {
      control = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Ouvrir',
          onPressed: d.available ? () => _call(d, 'open_cover') : null,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Stop',
          onPressed: d.available ? () => _call(d, 'stop_cover') : null,
          icon: const Icon(Icons.stop_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Fermer',
          onPressed: d.available ? () => _call(d, 'close_cover') : null,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ]);
    } else if (d.domain == 'climate' && d.target != null) {
      control = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '−0,5 °C',
          onPressed: d.available ? () => _call(d, 'set_temperature', {'temperature': d.target! - 0.5}) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        IconButton(
          tooltip: '+0,5 °C',
          onPressed: d.available ? () => _call(d, 'set_temperature', {'temperature': d.target! + 0.5}) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]);
    } else if (d.domain == 'lock') {
      control = TextButton(
        onPressed: d.available ? () => _call(d, d.state == 'locked' ? 'unlock' : 'lock') : null,
        child: Text(d.state == 'locked' ? 'Ouvrir' : 'Verrouiller'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (label.isNotEmpty)
                  Text(label, style: const TextStyle(color: panelMuted, fontSize: 12)),
              ],
            ),
          ),
          ?control,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Agenda

class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key, required this.client, required this.now});

  final HaClient client;
  final DateTime now;

  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

/// Days shown in the agenda tab.
const kAgendaDays = 7;

class _AgendaTabState extends State<AgendaTab> with _LiveTab<AgendaTab, List<AgendaEvent>> {
  @override
  HaClient get client => widget.client;

  DateTime get _start => DateTime(widget.now.year, widget.now.month, widget.now.day);

  @override
  Future<List<AgendaEvent>> load() =>
      client.fetchEvents(_start, DateTime(_start.year, _start.month, _start.day + kAgendaDays));

  @override
  Widget build(BuildContext context) {
    return frame((events) {
      final days = groupByDay(events, _start, kAgendaDays);
      return [
        if (days.isEmpty) PanelNote('Rien de prévu ces $kAgendaDays prochains jours.'),
        for (final day in days.entries)
          PanelSection(
            title: _dayTitle(day.key),
            children: [
              for (final e in day.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 112,
                        child: Text(eventTime(e), style: const TextStyle(color: panelMuted)),
                      ),
                      Expanded(child: Text(e.title)),
                    ],
                  ),
                ),
            ],
          ),
      ];
    });
  }

  String _dayTitle(DateTime day) {
    final diff = day.difference(_start).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Demain';
    return frenchDate(day);
  }
}

// ---------------------------------------------------------------- Tâches

class TasksTab extends StatefulWidget {
  const TasksTab({super.key, required this.client});

  final HaClient client;

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> with _LiveTab<TasksTab, List<TodoList>> {
  @override
  HaClient get client => widget.client;

  final _inputs = <String, TextEditingController>{};
  bool _showDone = false;

  @override
  Future<List<TodoList>> load() => client.fetchTodoLists();

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _add(TodoList list) async {
    final input = _inputs[list.id]!;
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await act(() => client.callService('todo', 'add_item', {'entity_id': list.id, 'item': text}));
  }

  Future<void> _check(TodoList list, TodoItem item, bool done) => act(() => client.callService(
        'todo',
        'update_item',
        {'entity_id': list.id, 'item': item.uid, 'status': done ? 'completed' : 'needs_action'},
      ));

  @override
  Widget build(BuildContext context) {
    return frame((lists) => [
          if (lists.isEmpty) const PanelNote('Aucune liste de tâches dans Home Assistant.'),
          if (lists.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _showDone = !_showDone),
                child: Text(_showDone ? 'Masquer les terminées' : 'Afficher les terminées'),
              ),
            ),
          for (final list in lists) _list(list),
        ]);
  }

  Widget _list(TodoList list) {
    final input = _inputs[list.id] ??= TextEditingController();
    final items = [for (final i in list.items) if (_showDone || !i.done) i];
    return PanelSection(
      title: list.name,
      children: [
        if (items.isEmpty) const PanelNote('Rien à faire.'),
        for (final item in items)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _check(list, item, !item.done),
            child: Row(
              children: [
                Checkbox(value: item.done, onChanged: (v) => _check(list, item, v ?? false)),
                Expanded(
                  child: Text(
                    item.summary,
                    style: item.done
                        ? const TextStyle(color: panelMuted, decoration: TextDecoration.lineThrough)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: input,
          onSubmitted: (_) => _add(list),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Ajouter une tâche…',
            suffixIcon: IconButton(
              tooltip: 'Ajouter',
              onPressed: () => _add(list),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
