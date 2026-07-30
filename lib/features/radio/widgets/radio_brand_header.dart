import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// The ExplorerOS Radio brand header: leading action (menu), a centered
/// radio-wave glyph + "EXPLOREROS RADIO" wordmark with the green
/// "EVERY PLACE HAS A STORY" tagline, and a trailing action (notifications).
class RadioBrandHeader extends StatelessWidget {
  const RadioBrandHeader({
    super.key,
    this.onMenu,
    this.onNotifications,
    this.showNotificationDot = true,
    this.leadingIcon = Icons.menu_rounded,
  });

  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;
  final bool showNotificationDot;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeaderIcon(icon: leadingIcon, onTap: onMenu),
        const Expanded(child: _Wordmark()),
        _HeaderIcon(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
          dot: showNotificationDot,
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_tethering_rounded, color: RD.green, size: 22),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RichText(
            text: const TextSpan(
              style: RD.wordmark,
              children: [
                TextSpan(text: 'EXPLORER'),
                TextSpan(text: 'OS', style: TextStyle(color: RD.green)),
                TextSpan(text: ' RADIO'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tick(),
            const SizedBox(width: 8),
            Text('EVERY PLACE HAS A STORY', style: RD.tagline),
            const SizedBox(width: 8),
            _tick(),
          ],
        ),
      ],
    );
  }

  Widget _tick() => Container(width: 14, height: 1.5, color: RD.greenDim);
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, this.onTap, this.dot = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: RD.textPrimary, size: 26),
              if (dot)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: RD.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: RD.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
