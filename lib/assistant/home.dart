// Music players, home devices and to-do lists read from Home Assistant.
//
// Pure Dart: parsing of `/api/states` and of the to-do service answers, so
// it can be tested without a network.

/// A media player (Spotify, Sonos, Google Cast…).
class MediaPlayer {
  const MediaPlayer({
    required this.id,
    required this.name,
    required this.state,
    this.title,
    this.artist,
    this.volume,
    this.picture,
    this.features = 0,
  });

  final String id;
  final String name;

  /// "playing", "paused", "idle", "off"…
  final String state;
  final String? title;
  final String? artist;

  /// 0 to 1.
  final double? volume;

  /// Path of the cover on Home Assistant ("/api/media_player_proxy/…").
  final String? picture;

  /// Home Assistant's `supported_features` bit mask.
  final int features;

  bool get playing => state == 'playing';
  bool get active => state == 'playing' || state == 'paused' || state == 'buffering';
  bool get canPause => features & 1 != 0 || features & 16384 != 0;
  bool get canSetVolume => features & 4 != 0;
  bool get canPrevious => features & 16 != 0;
  bool get canNext => features & 32 != 0;
}

/// A device of the house Nox can show and control.
class HomeDevice {
  const HomeDevice({
    required this.id,
    required this.name,
    required this.state,
    this.brightness,
    this.temperature,
    this.target,
  });

  final String id;
  final String name;
  final String state;

  /// Lights: 0 to 255.
  final int? brightness;

  /// Climate: current and target temperature.
  final double? temperature;
  final double? target;

  String get domain => id.substring(0, id.indexOf('.'));
  bool get on => state == 'on' || state == 'open' || state == 'unlocked' || state == 'heat';
  bool get available => state != 'unavailable' && state != 'unknown';

  /// Lights, switches, fans… switched on and off with a tap.
  bool get toggles => _toggleDomains.contains(domain);
}

const _toggleDomains = {'light', 'switch', 'fan', 'input_boolean'};

/// Domains shown in the "Maison" tab, in this order.
const homeDomains = ['scene', 'script', 'light', 'switch', 'fan', 'cover', 'climate', 'lock', 'input_boolean'];

const homeDomainLabels = {
  'scene': 'Scènes',
  'script': 'Scripts',
  'light': 'Lumières',
  'switch': 'Prises et interrupteurs',
  'fan': 'Ventilateurs',
  'cover': 'Volets',
  'climate': 'Chauffage',
  'lock': 'Serrures',
  'input_boolean': 'Interrupteurs virtuels',
};

String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;

String _name(Map s, String id) {
  final attrs = s['attributes'];
  return (attrs is Map ? _string(attrs['friendly_name']) : null) ?? id;
}

/// Media players in the answer of `/api/states`: playing ones first.
List<MediaPlayer> parseMediaPlayers(Object? states) {
  final players = <MediaPlayer>[];
  if (states is! List) return players;
  for (final s in states) {
    if (s is! Map) continue;
    final id = s['entity_id'];
    final state = s['state'];
    if (id is! String || !id.startsWith('media_player.') || state is! String) continue;
    if (state == 'unavailable' || state == 'unknown') continue;
    final attrs = s['attributes'] is Map ? s['attributes'] as Map : const {};
    final features = attrs['supported_features'];
    players.add(MediaPlayer(
      id: id,
      name: _name(s, id),
      state: state,
      title: _string(attrs['media_title']),
      artist: _string(attrs['media_artist']) ?? _string(attrs['media_album_name']),
      volume: _double(attrs['volume_level']),
      picture: _string(attrs['entity_picture']),
      features: features is int ? features : 0,
    ));
  }
  int rank(MediaPlayer p) => p.playing ? 0 : (p.active ? 1 : 2);
  players.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.compareTo(b.name);
  });
  return players;
}

/// Devices of the house in the answer of `/api/states`, grouped by domain
/// (in the order of [homeDomains]), sorted by name.
Map<String, List<HomeDevice>> parseHomeDevices(Object? states) {
  final byDomain = <String, List<HomeDevice>>{};
  if (states is! List) return byDomain;
  for (final s in states) {
    if (s is! Map) continue;
    final id = s['entity_id'];
    final state = s['state'];
    if (id is! String || state is! String || !id.contains('.')) continue;
    final domain = id.substring(0, id.indexOf('.'));
    if (!homeDomains.contains(domain)) continue;
    final attrs = s['attributes'] is Map ? s['attributes'] as Map : const {};
    // Groups made by integrations, hidden ones…
    if (attrs['hidden'] == true) continue;
    final brightness = attrs['brightness'];
    (byDomain[domain] ??= []).add(HomeDevice(
      id: id,
      name: _name(s, id),
      state: state,
      brightness: brightness is num ? brightness.round() : null,
      temperature: _double(attrs['current_temperature']),
      target: _double(attrs['temperature']),
    ));
  }
  for (final list in byDomain.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return {
    for (final d in homeDomains) d: ?byDomain[d],
  };
}

/// "Allumée", "Ouvert", "19,5 °C → 20 °C"…
String deviceLabel(HomeDevice d) {
  if (!d.available) return 'Indisponible';
  switch (d.domain) {
    case 'light':
      if (d.state != 'on') return 'Éteinte';
      final b = d.brightness;
      return b == null ? 'Allumée' : 'Allumée · ${(b * 100 / 255).round()} %';
    case 'cover':
      return const {
            'open': 'Ouvert',
            'closed': 'Fermé',
            'opening': 'S\'ouvre…',
            'closing': 'Se ferme…',
          }[d.state] ??
          d.state;
    case 'lock':
      return const {'locked': 'Verrouillée', 'unlocked': 'Déverrouillée'}[d.state] ?? d.state;
    case 'climate':
      String t(double v) => '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1).replaceAll('.', ',')} °C';
      final parts = [
        if (d.temperature != null) t(d.temperature!),
        if (d.target != null) '→ ${t(d.target!)}',
      ];
      final mode = const {'off': 'Arrêt', 'heat': 'Chauffe', 'cool': 'Clim', 'auto': 'Auto'}[d.state] ?? d.state;
      return [mode, ...parts].join(' · ');
    case 'scene':
    case 'script':
      return '';
    default:
      return d.state == 'on' ? 'Allumé' : 'Éteint';
  }
}

/// One item of a to-do list.
class TodoItem {
  const TodoItem({required this.uid, required this.summary, required this.done, this.due});

  final String uid;
  final String summary;
  final bool done;

  /// "2026-11-16" or a date-time, as given by Home Assistant.
  final String? due;
}

/// A to-do list and its items.
class TodoList {
  const TodoList({required this.id, required this.name, this.items = const []});

  final String id;
  final String name;
  final List<TodoItem> items;
}

/// To-do lists found in `/api/states`: entity_id → friendly name.
Map<String, String> parseTodoLists(Object? states) {
  final lists = <String, String>{};
  if (states is! List) return lists;
  for (final s in states) {
    if (s is! Map) continue;
    final id = s['entity_id'];
    if (id is! String || !id.startsWith('todo.')) continue;
    if (s['state'] == 'unavailable') continue;
    lists[id] = _name(s, id);
  }
  return lists;
}

/// Reads the answer of the `todo.get_items` service for [entityId]: items
/// still to do first, then done ones.
List<TodoItem> parseTodoList(Object? json, String entityId) {
  final items = <TodoItem>[];
  if (json is! Map) return items;
  final response = json['service_response'];
  if (response is! Map) return items;
  final list = response[entityId];
  final raw = list is Map ? list['items'] : null;
  if (raw is! List) return items;
  for (final item in raw) {
    if (item is! Map) continue;
    final summary = _string(item['summary']);
    final uid = _string(item['uid']);
    if (summary == null || uid == null) continue;
    items.add(TodoItem(
      uid: uid,
      summary: summary,
      done: item['status'] == 'completed',
      due: _string(item['due']),
    ));
  }
  final todo = [for (final i in items) if (!i.done) i];
  final done = [for (final i in items) if (i.done) i];
  return [...todo, ...done];
}
