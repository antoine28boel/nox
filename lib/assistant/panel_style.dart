import 'package:flutter/material.dart';

/// Colors and building blocks shared by the panel's tabs.
const panelBackground = Color(0xFF2B211A);
const panelCard = Color(0xFF3A2D23);
const panelTile = Color(0xFF46372B);
const panelText = Color(0xFFF5E9D3);
const panelMuted = Color(0xFFBFAE95);
const panelAccent = Color(0xFFF2B53A);
const panelError = Color(0xFFFF8F8F);

/// What the panel remembers between openings: folded sections and the Home
/// Assistant dashboard shown in the "Maison" tab. Kept in memory only when
/// [read] and [write] are not given (tests).
class PanelMemory {
  PanelMemory({this.read, this.write}) {
    final saved = read?.call(_collapsedKey);
    if (saved != null && saved.isNotEmpty) _collapsed.addAll(saved.split('\n'));
  }

  static const _collapsedKey = 'panel_collapsed';
  static const _dashboardKey = 'ha_dashboard';

  final String? Function(String key)? read;
  final void Function(String key, String value)? write;
  final _collapsed = <String>{};
  String? _dashboard;

  bool isCollapsed(String section) => _collapsed.contains(section);

  void toggle(String section) {
    if (!_collapsed.remove(section)) _collapsed.add(section);
    _save();
  }

  /// Forgets folded sections starting with [prefix] that [keep] rejects
  /// (days of the agenda that are over…).
  void prune(String prefix, bool Function(String section) keep) {
    final before = _collapsed.length;
    _collapsed.removeWhere((s) => s.startsWith(prefix) && !keep(s));
    if (_collapsed.length != before) _save();
  }

  void _save() => write?.call(_collapsedKey, _collapsed.join('\n'));

  /// The dashboard shown in the "Maison" tab: '' for none (every device),
  /// [defaultDashboard] for Home Assistant's default one, else its url path.
  String get dashboard => _dashboard ??= read?.call(_dashboardKey) ?? '';

  set dashboard(String value) {
    _dashboard = value;
    write?.call(_dashboardKey, value);
  }

  static const defaultDashboard = 'lovelace';
}

/// A rounded card with a small title. With [onToggle], a tap on the title
/// folds it; [count] is then shown next to the title while folded.
class PanelSection extends StatelessWidget {
  const PanelSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.collapsed = false,
    this.onToggle,
    this.count,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool collapsed;
  final VoidCallback? onToggle;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final folded = onToggle != null && collapsed;
    Widget heading = Row(
      children: [
        Expanded(
          child: Text(
            folded && count != null ? '${title.toUpperCase()}  ($count)' : title.toUpperCase(),
            style: const TextStyle(
              color: panelAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        ?trailing,
        if (onToggle != null)
          Icon(
            folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
            size: 18,
            color: panelAccent,
          ),
      ],
    );
    if (onToggle != null) {
      heading = InkWell(onTap: onToggle, borderRadius: BorderRadius.circular(6), child: heading);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.fromLTRB(14, 10, 14, folded ? 10 : 12),
      decoration: BoxDecoration(color: panelCard, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: folded ? 0 : 6),
            child: heading,
          ),
          if (!folded) ...children,
        ],
      ),
    );
  }
}

/// A muted line of text (empty list, status…).
class PanelNote extends StatelessWidget {
  const PanelNote(this.text, {super.key, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: TextStyle(color: error ? panelError : panelMuted, fontSize: 13)),
    );
  }
}
