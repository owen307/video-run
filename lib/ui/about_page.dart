import 'package:flutter/material.dart';

import '../brand.dart';
import '../theme/alpaca_theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlpacaColors.ink,
      appBar: AppBar(
        backgroundColor: AlpacaColors.ink,
        foregroundColor: AlpacaColors.text,
        title: const Text(appName, key: Key('about-title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const Center(child: RunIcon(size: 120)),
          const SizedBox(height: 18),
          const Text(
            appName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontSize: 42,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Version $appVersion',
            textAlign: TextAlign.center,
            style: TextStyle(color: AlpacaColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 22),
          const Text(
            'A dense touch console for program and preview switching, and for playlist transport. Cut and auto are large on purpose. When a host does not answer, that bank stays on screen and is marked MOCK.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Follow cues runs a mapped action when a matching cue arrives on the LAN link. Leave it off during a show until the map is the one you mean to run.',
            style: TextStyle(fontSize: 16, height: 1.4, color: AlpacaColors.muted),
          ),
        ],
      ),
    );
  }
}

class RunIcon extends StatelessWidget {
  const RunIcon({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        iconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
      ),
    );
  }
}
