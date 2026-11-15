import 'dart:async';

import 'package:flutter/material.dart';

import 'panel_style.dart';
import 'spotify.dart';
import 'spotify_client.dart';

/// Spotify at the top of the "Musique" tab: what plays, controls, device,
/// search and playlists.
class SpotifySection extends StatefulWidget {
  const SpotifySection({super.key, required this.client});

  final SpotifyClient client;

  @override
  State<SpotifySection> createState() => _SpotifySectionState();
}

class _SpotifySectionState extends State<SpotifySection> {
  SpotifyPlayback? _playback;
  bool _loaded = false;
  String? _error;
  Timer? _poll;
  Timer? _tick;

  /// When [_playback] was read, to move the progress bar between reads.
  DateTime _readAt = DateTime.now();

  double? _seeking;
  double? _volume;

  final _search = TextEditingController();
  List<SpotifyItem>? _results;
  bool _searching = false;

  List<SpotifyItem>? _playlists;
  bool _showPlaylists = false;

  SpotifyClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_playback?.playing == true && _seeking == null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final playback = await _client.playback();
      if (!mounted) return;
      setState(() {
        _playback = playback;
        _readAt = DateTime.now();
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  String _message(Object e) => e is SpotifyException ? e.message : 'Spotify injoignable';

  /// Runs a command, then reads the playback again (Spotify needs a moment).
  Future<void> _do(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _refresh();
  }

  int get _progress {
    final p = _playback;
    if (p == null) return 0;
    if (!p.playing) return p.progressMs;
    final moved = p.progressMs + DateTime.now().difference(_readAt).inMilliseconds;
    return p.durationMs > 0 ? moved.clamp(0, p.durationMs) : moved;
  }

  Future<void> _runSearch() async {
    final text = _search.text.trim();
    if (text.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _client.search(text);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _togglePlaylists() async {
    setState(() => _showPlaylists = !_showPlaylists);
    if (!_showPlaylists || _playlists != null) return;
    try {
      final lists = await _client.playlists();
      if (mounted) setState(() => _playlists = lists);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  /// Plays [item] on the current device, or on the first one available.
  Future<void> _play(SpotifyItem item) => _do(() async {
    var device = _playback?.device?.id;
    if (device == null) {
      final devices = await _client.devices();
      if (devices.isNotEmpty) device = devices.first.id;
    }
    await _client.play(item: item, device: device);
  });

  @override
  Widget build(BuildContext context) {
    final p = _playback;
    return PanelSection(
      title: 'Spotify',
      trailing: _devicesButton(),
      children: [
        if (_error != null) PanelNote(_error!, error: true),
        if (!_loaded && _error == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (p == null)
          const PanelNote(
            'Rien en cours. Choisis un appareil (en haut à droite) ou lance '
            'une playlist.',
          )
        else
          ..._nowPlaying(p),
        const SizedBox(height: 6),
        _searchField(),
        if (_results case final results?) ...[
          if (results.isEmpty) const PanelNote('Aucun résultat.'),
          for (final item in results) _itemRow(item),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _togglePlaylists,
            icon: Icon(_showPlaylists ? Icons.expand_less : Icons.expand_more, size: 18),
            label: const Text('Mes playlists'),
          ),
        ),
        if (_showPlaylists) ...[
          if (_playlists == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_playlists!.isEmpty)
            const PanelNote('Aucune playlist.')
          else
            for (final item in _playlists!) _itemRow(item),
        ],
      ],
    );
  }

  List<Widget> _nowPlaying(SpotifyPlayback p) {
    final cover = p.cover;
    final device = p.device;
    final duration = p.durationMs;
    final progress = (_seeking ?? _progress.toDouble()).clamp(0.0, duration.toDouble());
    final volume = _volume ?? device?.volume?.toDouble();
    return [
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 64,
              height: 64,
              color: panelBackground,
              child: cover == null
                  ? const Icon(Icons.music_note, color: panelMuted)
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const Icon(Icons.music_note, color: panelMuted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title ?? 'Lecture en cours',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (p.artists != null)
                  Text(
                    p.artists!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: panelMuted),
                  ),
                if (device != null)
                  Text(
                    'Sur ${device.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: panelAccent, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
      if (duration > 0)
        Row(
          children: [
            Text(
              minutesSeconds(progress.round()),
              style: const TextStyle(color: panelMuted, fontSize: 11),
            ),
            Expanded(
              child: Slider(
                value: progress,
                max: duration.toDouble(),
                onChanged: (v) => setState(() => _seeking = v),
                onChangeEnd: (v) async {
                  await _do(() => _client.seek(v.round()));
                  if (mounted) setState(() => _seeking = null);
                },
              ),
            ),
            Text(minutesSeconds(duration), style: const TextStyle(color: panelMuted, fontSize: 11)),
          ],
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: p.shuffle ? 'Lecture aléatoire activée' : 'Lecture aléatoire',
            onPressed: () => _do(() => _client.setShuffle(!p.shuffle)),
            icon: Icon(Icons.shuffle_rounded, color: p.shuffle ? panelAccent : panelMuted),
          ),
          IconButton(
            tooltip: 'Précédent',
            onPressed: () => _do(_client.previous),
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton.filled(
            tooltip: p.playing ? 'Pause' : 'Lecture',
            onPressed: () => _do(p.playing ? _client.pause : () => _client.play()),
            icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: 'Suivant',
            onPressed: () => _do(_client.next),
            icon: const Icon(Icons.skip_next_rounded),
          ),
          const SizedBox(width: 40),
        ],
      ),
      if (volume != null)
        Row(
          children: [
            const Icon(Icons.volume_down_rounded, size: 18, color: panelMuted),
            Expanded(
              child: Slider(
                value: volume.clamp(0, 100),
                max: 100,
                onChanged: (v) => setState(() => _volume = v),
                onChangeEnd: (v) async {
                  await _do(() => _client.setVolume(v.round()));
                  if (mounted) setState(() => _volume = null);
                },
              ),
            ),
            const Icon(Icons.volume_up_rounded, size: 18, color: panelMuted),
          ],
        ),
    ];
  }

  Widget _devicesButton() {
    return Builder(
      builder: (context) => IconButton(
        tooltip: 'Choisir l\'appareil',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: const Icon(Icons.speaker_group_outlined, size: 18, color: panelAccent),
        onPressed: () => _chooseDevice(context),
      ),
    );
  }

  /// Devices come and go: they are read when the menu opens.
  Future<void> _chooseDevice(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    List<SpotifyDevice> devices;
    try {
      devices = await _client.devices();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
      return;
    }
    if (!mounted || !context.mounted || box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final chosen = await showMenu<SpotifyDevice>(
      context: context,
      position: RelativeRect.fromRect(topLeft & box.size, Offset.zero & overlay.size),
      items: [
        if (devices.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('Aucun appareil : ouvre Spotify.')),
        for (final d in devices)
          PopupMenuItem(
            value: d,
            child: Row(
              children: [
                Icon(_deviceIcon(d.type), size: 18, color: d.active ? panelAccent : null),
                const SizedBox(width: 10),
                Expanded(child: Text(d.name)),
                if (d.active) const Icon(Icons.check_rounded, size: 16, color: panelAccent),
              ],
            ),
          ),
      ],
    );
    if (chosen != null && !chosen.active) await _do(() => _client.transfer(chosen.id));
  }

  IconData _deviceIcon(String type) => switch (type.toLowerCase()) {
    'computer' => Icons.computer_rounded,
    'smartphone' => Icons.smartphone_rounded,
    'tablet' => Icons.tablet_rounded,
    'tv' => Icons.tv_rounded,
    _ => Icons.speaker_rounded,
  };

  Widget _searchField() {
    return TextField(
      controller: _search,
      onSubmitted: (_) => _runSearch(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Rechercher un titre, une playlist…',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (_results != null
                  ? IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() {
                        _search.clear();
                        _results = null;
                      }),
                    )
                  : null),
      ),
    );
  }

  Widget _itemRow(SpotifyItem item) {
    final image = item.image;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _play(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 36,
                height: 36,
                color: panelBackground,
                child: image == null
                    ? Icon(
                        item.isTrack ? Icons.music_note : Icons.queue_music,
                        size: 18,
                        color: panelMuted,
                      )
                    : Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.music_note, size: 18, color: panelMuted),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: panelMuted, fontSize: 12),
                    ),
                ],
              ),
            ),
            const Icon(Icons.play_arrow_rounded, size: 18, color: panelMuted),
          ],
        ),
      ),
    );
  }
}
