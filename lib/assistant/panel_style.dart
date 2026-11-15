import 'package:flutter/material.dart';

/// Colors and building blocks shared by the panel's tabs.
const panelBackground = Color(0xFF2B211A);
const panelCard = Color(0xFF3A2D23);
const panelText = Color(0xFFF5E9D3);
const panelMuted = Color(0xFFBFAE95);
const panelAccent = Color(0xFFF2B53A);
const panelError = Color(0xFFFF8F8F);

/// A rounded card with a small title.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: panelCard, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: panelAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ...children,
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
