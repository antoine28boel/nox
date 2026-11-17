import 'dart:async';

import 'package:flutter/material.dart';

import 'actual_client.dart';
import 'brief.dart';
import 'budget.dart';
import 'ha_client.dart';
import 'ha_dashboard.dart';
import 'home.dart';
import 'panel_style.dart';
import 'spotify_client.dart';
import 'spotify_view.dart';
import 'today.dart';
import 'vikunja.dart';
import 'vikunja_client.dart';

/// Shared behavior of the live tabs: loads from Home Assistant when shown,
/// again every [every] while visible, and after each action.
mixin _LiveTab<T extends StatefulWidget, D> on State<T> {
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
    } on VikunjaException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on ActualException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = unreachable);
    } finally {
      loading = false;
      if (mounted) setState(() {});
    }
  }

  /// Shown when the server does not answer.
  String get unreachable => 'Home Assistant injoignable';

  /// Runs a service call, then reloads.
  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } on HaException catch (e) {
      if (mounted) setState(() => error = e.message);
      return;
    } on ActualException catch (e) {
      if (mounted) setState(() => error = e.message);
      return;
    } catch (_) {
      if (mounted) setState(() => error = unreachable);
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
  const MusicTab({super.key, this.client, this.spotify});

  /// Home Assistant's players, when connected.
  final HaClient? client;

  /// Spotify, shown first, when connected.
  final SpotifyClient? spotify;

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> with _LiveTab<MusicTab, List<MediaPlayer>> {
  HaClient get client => widget.client!;
  @override
  Duration? get every => widget.client == null ? null : const Duration(seconds: 3);

  /// Volume being dragged, per player, so polling does not fight the slider.
  final _dragging = <String, double>{};

  @override
  Future<List<MediaPlayer>> load() async {
    if (widget.client == null) return const [];
    final players = parseMediaPlayers(await client.states());
    // Spotify is already shown above, with more controls.
    if (widget.spotify == null) return players;
    return [
      for (final p in players)
        if (!p.id.startsWith('media_player.spotify')) p,
    ];
  }

  Future<void> _call(MediaPlayer p, String service, [Map<String, Object?> extra = const {}]) =>
      act(() => client.callService('media_player', service, {'entity_id': p.id, ...extra}));

  @override
  Widget build(BuildContext context) {
    return frame(
      (players) => [
        if (widget.spotify case final spotify?) SpotifySection(client: spotify),
        if (players.isEmpty && widget.client != null)
          const PanelNote('Aucun autre lecteur dans Home Assistant.'),
        for (final p in players) _player(p),
      ],
    );
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
                  Text(
                    p.active ? (p.title ?? 'Lecture en cours') : _idle(p.state),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (p.active && p.artist != null)
                    Text(
                      p.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: panelMuted),
                    ),
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
                    await _call(p, 'volume_set', {
                      'volume_level': double.parse(v.toStringAsFixed(2)),
                    });
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
      const {
        'off': 'Éteint',
        'idle': 'En attente',
        'on': 'Allumé',
        'standby': 'En veille',
      }[state] ??
      state;
}

// ---------------------------------------------------------------- Maison

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.client, required this.memory});

  final HaClient client;
  final PanelMemory memory;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

/// Every entity by id, and the devices of the house by domain.
typedef _HomeData = ({Map<String, HomeDevice> byId, Map<String, List<HomeDevice>> byDomain});

class _HomeTabState extends State<HomeTab> with _LiveTab<HomeTab, _HomeData> {
  HaClient get client => widget.client;
  PanelMemory get memory => widget.memory;

  @override
  Duration get every => const Duration(seconds: 10);

  List<HaDashboardInfo>? _dashboards;

  /// Views of the chosen dashboard; null while loading or without one.
  List<DashboardView>? _views;
  String? _dashboardNote;
  int _view = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboards();
    _loadDashboard();
  }

  @override
  Future<_HomeData> load() async {
    final states = await client.states();
    return (byId: parseEntities(states), byDomain: parseHomeDevices(states));
  }

  Future<void> _loadDashboards() async {
    try {
      final list = await client.fetchDashboards();
      if (mounted) setState(() => _dashboards = list);
    } catch (_) {
      // The picker then only offers "every device".
    }
  }

  Future<void> _loadDashboard() async {
    final path = memory.dashboard;
    setState(() {
      _views = null;
      _dashboardNote = null;
      _view = 0;
    });
    if (path.isEmpty) return;
    try {
      final views = await client.fetchDashboard(path);
      if (!mounted || memory.dashboard != path) return;
      setState(() {
        _views = views;
        if (views.isEmpty) {
          _dashboardNote =
              'Ce tableau de bord est généré par Home Assistant : Nox montre tous les appareils.';
        }
      });
    } on HaException catch (e) {
      if (mounted) setState(() => _dashboardNote = e.message);
    } catch (_) {
      if (mounted) setState(() => _dashboardNote = 'Tableau de bord illisible.');
    }
  }

  void _pick(String? path) {
    if (path == null || path == memory.dashboard) return;
    memory.dashboard = path;
    _loadDashboard();
  }

  Future<void> _call(HomeDevice d, String service, [Map<String, Object?> extra = const {}]) =>
      act(() => client.callService(d.domain, service, {'entity_id': d.id, ...extra}));

  @override
  Widget build(BuildContext context) {
    return frame((data) {
      final views = _views;
      final chosen = memory.dashboard;
      return [
        _picker(),
        if (_dashboardNote != null) PanelNote(_dashboardNote!),
        if (chosen.isNotEmpty && views == null && _dashboardNote == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (views != null && views.isNotEmpty)
          ..._dashboard(views, data.byId)
        else ...[
          if (data.byDomain.isEmpty) const PanelNote('Aucun appareil trouvé dans Home Assistant.'),
          for (final entry in data.byDomain.entries)
            _group('home::${entry.key}', homeDomainLabels[entry.key] ?? entry.key, entry.value),
        ],
      ];
    });
  }

  Widget _picker() {
    final dashboards = _dashboards ?? const <HaDashboardInfo>[];
    final chosen = memory.dashboard;
    final known = chosen.isEmpty || dashboards.any((d) => d.urlPath == chosen);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.dashboard_rounded, size: 16, color: panelMuted),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: chosen,
                isExpanded: true,
                isDense: true,
                dropdownColor: panelCard,
                style: const TextStyle(color: panelText, fontSize: 13),
                iconEnabledColor: panelAccent,
                onChanged: _pick,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tous les appareils')),
                  for (final d in dashboards)
                    DropdownMenuItem(value: d.urlPath, child: Text(d.title)),
                  if (!known) DropdownMenuItem(value: chosen, child: Text(chosen)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _dashboard(List<DashboardView> views, Map<String, HomeDevice> byId) {
    final view = views[_view.clamp(0, views.length - 1)];
    final key = 'home:${memory.dashboard}:${view.title}';
    return [
      if (views.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              for (var i = 0; i < views.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(views[i].title),
                    selected: views[i] == view,
                    onSelected: (_) => setState(() => _view = i),
                  ),
                ),
            ],
          ),
        ),
      for (var i = 0; i < view.groups.length; i++)
        _group(
          '$key:${view.groups[i].title ?? i}',
          view.groups[i].title ?? (i == 0 ? view.title : 'Autres'),
          [
            for (final e in view.groups[i].entities)
              if (byId[e.id] case final d?) d.named(e.name),
          ],
        ),
    ];
  }

  Widget _group(String key, String title, List<HomeDevice> devices) {
    if (devices.isEmpty) return const SizedBox.shrink();
    return PanelSection(
      title: title,
      collapsed: memory.isCollapsed(key),
      onToggle: () => setState(() => memory.toggle(key)),
      count: devices.length,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final half = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final d in devices)
                  SizedBox(width: d.domain == 'climate' ? box.maxWidth : half, child: _tile(d)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// What a tap on the tile does, if anything.
  VoidCallback? _tap(HomeDevice d) {
    if (!d.available) return null;
    if (d.toggles) return () => _call(d, 'toggle');
    return switch (d.domain) {
      'scene' || 'script' => () => _call(d, 'turn_on'),
      'button' || 'input_button' => () => _call(d, 'press'),
      'cover' => () => _call(d, 'toggle'),
      'lock' => () => _call(d, d.state == 'locked' ? 'unlock' : 'lock'),
      'media_player' => () => _call(d, 'media_play_pause'),
      _ => null,
    };
  }

  Widget _tile(HomeDevice d) {
    final active = d.available && (d.on || d.state == 'playing' || d.state == 'home');
    final label = deviceLabel(d);
    final onTap = _tap(d);
    Widget? controls;
    if (d.domain == 'climate' && d.target != null && d.available) {
      controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '−0,5 °C',
            visualDensity: VisualDensity.compact,
            onPressed: () => _call(d, 'set_temperature', {'temperature': d.target! - 0.5}),
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          IconButton(
            tooltip: '+0,5 °C',
            visualDensity: VisualDensity.compact,
            onPressed: () => _call(d, 'set_temperature', {'temperature': d.target! + 0.5}),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      );
    }
    return Material(
      color: active ? panelAccent.withValues(alpha: 0.16) : panelTile,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
          child: Row(
            children: [
              Icon(
                deviceIcon(d),
                size: 20,
                color: !d.available
                    ? panelMuted.withValues(alpha: 0.5)
                    : active
                    ? panelAccent
                    : panelMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (label.isNotEmpty)
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: active ? panelText : panelMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              ?controls,
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon of a device's tile.
IconData deviceIcon(HomeDevice d) {
  switch (d.domain) {
    case 'light':
      return d.on ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded;
    case 'switch':
    case 'input_boolean':
      return Icons.power_settings_new_rounded;
    case 'fan':
      return Icons.air_rounded;
    case 'cover':
      return Icons.window_rounded;
    case 'climate':
      return Icons.thermostat_rounded;
    case 'lock':
      return d.state == 'locked' ? Icons.lock_rounded : Icons.lock_open_rounded;
    case 'scene':
      return Icons.palette_rounded;
    case 'script':
      return Icons.play_arrow_rounded;
    case 'button':
    case 'input_button':
      return Icons.touch_app_rounded;
    case 'automation':
      return Icons.auto_mode_rounded;
    case 'media_player':
      return Icons.speaker_rounded;
    case 'person':
    case 'device_tracker':
      return Icons.person_rounded;
    case 'binary_sensor':
      return switch (d.deviceClass) {
        'door' || 'garage_door' || 'opening' => Icons.sensor_door_rounded,
        'window' => Icons.window_rounded,
        'motion' || 'occupancy' || 'presence' => Icons.directions_walk_rounded,
        'moisture' => Icons.water_drop_rounded,
        'smoke' || 'gas' || 'problem' || 'safety' => Icons.warning_amber_rounded,
        _ => Icons.sensors_rounded,
      };
    case 'sensor':
      return switch (d.deviceClass) {
        'temperature' => Icons.thermostat_rounded,
        'humidity' => Icons.water_drop_rounded,
        'power' || 'energy' || 'current' || 'voltage' => Icons.bolt_rounded,
        'battery' => Icons.battery_std_rounded,
        'illuminance' => Icons.wb_sunny_rounded,
        _ => Icons.sensors_rounded,
      };
    default:
      return Icons.circle_outlined;
  }
}

// ---------------------------------------------------------------- Agenda

class AgendaTab extends StatefulWidget {
  const AgendaTab({
    super.key,
    required this.client,
    required this.memory,
    required this.now,
    this.brief,
  });

  final HaClient client;
  final PanelMemory memory;
  final DateTime now;

  /// Today's brief, shown above the agenda.
  final Brief? brief;

  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

/// Days shown in the agenda tab.
const kAgendaDays = 7;

class _AgendaTabState extends State<AgendaTab> with _LiveTab<AgendaTab, List<AgendaEvent>> {
  HaClient get client => widget.client;

  DateTime get _start => DateTime(widget.now.year, widget.now.month, widget.now.day);

  PanelMemory get memory => widget.memory;

  static const _brief = 'agenda:brief';

  String _dayKey(DateTime day) =>
      'agenda:${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    // Days that are over keep no folded state.
    final today = _dayKey(_start);
    memory.prune('agenda:2', (key) => key.compareTo(today) >= 0);
  }

  void _toggle(String key) => setState(() => memory.toggle(key));

  @override
  Future<List<AgendaEvent>> load() =>
      client.fetchEvents(_start, DateTime(_start.year, _start.month, _start.day + kAgendaDays));

  @override
  Widget build(BuildContext context) {
    return frame((events) {
      final days = groupByDay(events, _start, kAgendaDays);
      return [
        if (widget.brief case final brief?)
          PanelSection(
            title: 'Brief',
            collapsed: memory.isCollapsed(_brief),
            onToggle: () => _toggle(_brief),
            children: [
              Text(brief.text, style: const TextStyle(height: 1.4)),
              if (brief.byAi)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Rédigé par l\'IA de Home Assistant',
                    style: TextStyle(color: panelMuted, fontSize: 11),
                  ),
                ),
            ],
          ),
        if (days.isEmpty) PanelNote('Rien de prévu ces $kAgendaDays prochains jours.'),
        for (final day in days.entries)
          PanelSection(
            title: _dayTitle(day.key),
            collapsed: memory.isCollapsed(_dayKey(day.key)),
            onToggle: () => _toggle(_dayKey(day.key)),
            count: day.value.length,
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
  const TasksTab({super.key, required this.client, required this.memory});

  final HaClient client;
  final PanelMemory memory;

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> with _LiveTab<TasksTab, List<TodoList>> {
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

  Future<void> _check(TodoList list, TodoItem item, bool done) => act(
    () => client.callService('todo', 'update_item', {
      'entity_id': list.id,
      'item': item.uid,
      'status': done ? 'completed' : 'needs_action',
    }),
  );

  @override
  Widget build(BuildContext context) {
    return frame(
      (lists) => [
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
      ],
    );
  }

  Widget _list(TodoList list) {
    final input = _inputs[list.id] ??= TextEditingController();
    final items = [
      for (final i in list.items)
        if (_showDone || !i.done) i,
    ];
    final key = 'tasks:${list.id}';
    return PanelSection(
      title: list.name,
      collapsed: widget.memory.isCollapsed(key),
      onToggle: () => setState(() => widget.memory.toggle(key)),
      count: list.items.where((i) => !i.done).length,
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

// ---------------------------------------------------------------- Suivi

class TrackingTab extends StatefulWidget {
  const TrackingTab({super.key, required this.client});

  final VikunjaClient client;

  @override
  State<TrackingTab> createState() => _TrackingTabState();
}

class _TrackingTabState extends State<TrackingTab> with _LiveTab<TrackingTab, Tracking> {
  @override
  Duration get every => const Duration(minutes: 1);

  @override
  String get unreachable => 'Vikunja injoignable';

  @override
  Future<Tracking> load() => widget.client.fetchTracking();

  @override
  Widget build(BuildContext context) {
    return frame(
      (t) => [
        PanelSection(
          title: 'En cours',
          children: [
            if (t.inProgress.isEmpty) const PanelNote('Aucune tâche en cours.'),
            for (final task in t.inProgress) _task(task, t, showProject: true),
          ],
        ),
        if (t.claude case final claude?)
          PanelSection(
            title: 'Tâches de Claude',
            children: [
              if (claude.isEmpty) const PanelNote('Rien en attente.'),
              for (final task in claude) _task(task, t),
            ],
          ),
        PanelSection(
          title: 'Projets',
          children: [
            if (t.projects.isEmpty) const PanelNote('Aucun projet dans Vikunja.'),
            for (final p in t.projects) _project(p),
          ],
        ),
      ],
    );
  }

  Widget _task(VkTask task, Tracking t, {bool showProject = false}) {
    final started = t.inProgressIds.contains(task.id);
    final due = task.due;
    final late = due != null && due.isBefore(DateTime.now());
    final details = [
      if (showProject) ?t.projectNames[task.projectId],
      if (due != null) 'échéance ${frenchDate(due)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              started ? Icons.play_circle_outline_rounded : Icons.radio_button_unchecked,
              size: 16,
              color: started ? panelAccent : panelMuted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: TextStyle(color: late ? panelError : panelMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _project(ProjectProgress p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.path, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(
                [
                  if (p.inProgress > 0) '${p.inProgress} en cours',
                  '${p.done}/${p.total}',
                ].join(' · '),
                style: const TextStyle(color: panelMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p.ratio,
              minHeight: 5,
              color: panelAccent,
              backgroundColor: panelBackground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Budget

class BudgetTab extends StatefulWidget {
  const BudgetTab({super.key, required this.client, required this.memory, required this.now});

  final ActualClient client;
  final PanelMemory memory;
  final DateTime now;

  @override
  State<BudgetTab> createState() => _BudgetTabState();
}

/// Operations listed in the "Budget" tab.
const kBudgetOperations = 15;

class _BudgetTabState extends State<BudgetTab> with _LiveTab<BudgetTab, Finances> {
  PanelMemory get memory => widget.memory;

  @override
  Duration get every => const Duration(minutes: 2);

  @override
  String get unreachable => 'actual-http-api injoignable';

  @override
  Future<Finances> load() => widget.client.fetchFinances(widget.now);

  final _amount = TextEditingController();
  final _payee = TextEditingController();
  String? _account;
  String? _envelope;
  String? _formError;
  bool _adding = false;

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() => memory.toggle(key));

  Future<void> _add(Finances f) async {
    final cents = parseEuros(_amount.text);
    final account = _account ?? (f.onBudget.isEmpty ? null : f.onBudget.first.id);
    if (cents == null) return setState(() => _formError = 'Montant invalide.');
    if (account == null) return setState(() => _formError = 'Aucun compte dans le budget.');
    setState(() {
      _adding = true;
      _formError = null;
    });
    await act(
      () => widget.client.addExpense(
        accountId: account,
        cents: cents,
        date: DateTime.now(),
        payee: _payee.text,
        categoryId: _envelope,
      ),
    );
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (error == null) {
        _amount.clear();
        _payee.clear();
        _envelope = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return frame((f) {
      final names = {for (final a in f.accounts) a.id: a.name};
      final operations = f.operations.take(kBudgetOperations).toList();
      return [
        _summary(f),
        _expenseForm(f),
        _accounts(f),
        if (f.month.groups.isEmpty) const PanelNote('Aucune enveloppe ce mois-ci.'),
        for (final g in f.month.groups) _group(g),
        PanelSection(
          title: 'Dernières opérations',
          collapsed: memory.isCollapsed('budget:operations'),
          onToggle: () => _toggle('budget:operations'),
          count: operations.length,
          children: [
            if (operations.isEmpty) const PanelNote('Aucune opération ces 30 derniers jours.'),
            for (final o in operations)
              _operation(o, f.onBudget.length > 1 ? names[o.accountId] : null),
          ],
        ),
      ];
    });
  }

  Widget _line(String label, int cents, {Color? color, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: bold ? panelText : panelMuted)),
        ),
        Text(
          formatEuros(cents),
          style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    ),
  );

  Widget _summary(Finances f) {
    final m = f.month;
    final over = m.envelopes.where((e) => e.overspent).length;
    return PanelSection(
      title: monthTitle(m.month.isEmpty ? monthKey(widget.now) : m.month),
      children: [
        _line('Sur les comptes', f.total, bold: true),
        _line('À budgéter', m.toBudget, color: m.toBudget < 0 ? panelError : null),
        _line('Dépensé ce mois', m.spent),
        if (m.income != 0) _line('Revenus du mois', m.income),
        if (over > 0)
          PanelNote(
            over == 1 ? '1 enveloppe dans le rouge.' : '$over enveloppes dans le rouge.',
            error: true,
          ),
      ],
    );
  }

  Widget _expenseForm(Finances f) {
    const key = 'budget:add';
    final accounts = f.onBudget;
    final account = accounts.any((a) => a.id == _account) ? _account : accounts.firstOrNull?.id;
    final envelopes = f.month.envelopes.toList();
    final envelope = envelopes.any((e) => e.id == _envelope) ? _envelope : null;
    DropdownButton<String?> dropdown(
      String? value,
      List<DropdownMenuItem<String?>> items,
      ValueChanged<String?> onChanged,
    ) => DropdownButton<String?>(
      value: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: panelCard,
      style: const TextStyle(color: panelText, fontSize: 13),
      iconEnabledColor: panelAccent,
      underline: const SizedBox.shrink(),
      onChanged: _adding ? null : onChanged,
      items: items,
    );
    return PanelSection(
      title: 'Nouvelle dépense',
      collapsed: memory.isCollapsed(key),
      onToggle: () => _toggle(key),
      children: [
        Row(
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _amount,
                enabled: !_adding,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Montant',
                  suffixText: '€',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _payee,
                enabled: !_adding,
                onSubmitted: (_) => _add(f),
                decoration: const InputDecoration(isDense: true, labelText: 'Bénéficiaire'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: dropdown(account, [
                for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ], (v) => setState(() => _account = v)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: dropdown(envelope, [
                const DropdownMenuItem(value: null, child: Text('Sans enveloppe')),
                for (final e in envelopes) DropdownMenuItem(value: e.id, child: Text(e.name)),
              ], (v) => setState(() => _envelope = v)),
            ),
          ],
        ),
        if (_formError != null) PanelNote(_formError!, error: true),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _adding ? null : () => _add(f),
            child: Text(_adding ? 'Ajout…' : 'Ajouter'),
          ),
        ),
      ],
    );
  }

  Widget _accounts(Finances f) {
    const key = 'budget:accounts';
    return PanelSection(
      title: 'Comptes',
      collapsed: memory.isCollapsed(key),
      onToggle: () => _toggle(key),
      count: f.accounts.length,
      children: [
        if (f.accounts.isEmpty) const PanelNote('Aucun compte ouvert.'),
        for (final a in f.onBudget)
          _line(a.name, a.balance, color: a.balance < 0 ? panelError : null),
        if (f.offBudget.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 2),
            child: Text('Hors budget', style: TextStyle(color: panelMuted, fontSize: 11)),
          ),
          for (final a in f.offBudget) _line(a.name, a.balance),
        ],
      ],
    );
  }

  Widget _group(EnvelopeGroup g) {
    final key = 'budget:group:${g.name}';
    return PanelSection(
      title: g.name,
      collapsed: memory.isCollapsed(key),
      onToggle: () => _toggle(key),
      count: g.envelopes.length,
      trailing: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          formatEuros(g.balance),
          style: TextStyle(color: g.balance < 0 ? panelError : panelMuted, fontSize: 12),
        ),
      ),
      children: [for (final e in g.envelopes) _envelopeRow(e)],
    );
  }

  Widget _envelopeRow(Envelope e) {
    final color = e.overspent
        ? panelError
        : e.low
        ? panelAccent
        : panelText;
    final ratio = e.budgeted > 0
        ? (e.spent / e.budgeted).clamp(0.0, 1.0)
        : (e.spent > 0 ? 1.0 : 0.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(
                formatEuros(e.balance),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              color: e.overspent ? panelError : panelAccent,
              backgroundColor: panelBackground,
            ),
          ),
          if (e.budgeted > 0 || e.spent != 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${formatEuros(e.spent)} dépensés sur ${formatEuros(e.budgeted)}',
                style: const TextStyle(color: panelMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _operation(Operation o, String? account) {
    final details = [?o.category, ?account, ?o.notes].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${o.date.day.toString().padLeft(2, '0')}/${o.date.month.toString().padLeft(2, '0')}',
              style: const TextStyle(color: panelMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.payee, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (details.isNotEmpty)
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: panelMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            formatEuros(o.amount, sign: true),
            style: TextStyle(
              color: o.amount > 0 ? panelAccent : panelText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
