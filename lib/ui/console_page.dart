import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../models/console_models.dart';
import '../protocol/alpaca_link.dart';
import '../state/console_controller.dart';
import '../theme/alpaca_theme.dart';
import 'about_page.dart';
import 'setup_page.dart';

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key, required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AlpacaColors.ink,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1040;
                final banner = _banner(controller);
                return Column(
                  children: [
                    _TopBar(controller: controller),
                    if (banner != null) _MockBanner(controller: controller, text: banner),
                    if (controller.eventLog.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Text(
                          controller.eventLog.first,
                          key: const Key('latest-event'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AlpacaText.mono,
                        ),
                      ),
                    Expanded(
                      child: wide
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(flex: 6, child: _SwitcherPane(controller: controller)),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 4, child: _PresentationPane(controller: controller)),
                                ],
                              ),
                            )
                          : _StackedConsole(controller: controller),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

String? _banner(ConsoleController controller) {
  final parts = <String>[];
  if (controller.switcherSide == LinkSide.mock) {
    parts.add('Switcher: ${controller.switcherNote}');
  }
  if (controller.presentationSide == LinkSide.mock) {
    parts.add('Presentation: ${controller.presentationNote}');
  }
  if (parts.isEmpty) return null;
  return 'MOCK · ${parts.join('  ·  ')}';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final linkUp = controller.linkNote.startsWith('Listening');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const RunIcon(size: 40),
          const Text(
            appName,
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          _Chip(
            label: controller.switcherSide == LinkSide.live
                ? 'LIVE'
                : controller.switcherSide == LinkSide.connecting
                ? 'LINKING'
                : 'MOCK',
            tone: controller.switcherSide == LinkSide.live
                ? _Tone.live
                : controller.switcherSide == LinkSide.connecting
                ? _Tone.brass
                : _Tone.mock,
          ),
          _Chip(
            label: linkUp ? 'LINK $alpacaLinkPort' : 'LINK DOWN',
            tone: linkUp ? _Tone.live : _Tone.down,
          ),
          _FollowButton(controller: controller),
          _SendButton(controller: controller),
          IconButton(
            key: const Key('open-log'),
            tooltip: 'Event log',
            onPressed: () => _showLog(context, controller),
            icon: const Icon(Icons.notes_rounded),
            iconSize: 26,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          IconButton(
            key: const Key('open-setup'),
            tooltip: 'Links',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => SetupPage(controller: controller)),
              );
            },
            icon: const Icon(Icons.tune_rounded),
            iconSize: 26,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          IconButton(
            key: const Key('open-about'),
            tooltip: 'About',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutPage()),
              );
            },
            icon: const Icon(Icons.info_outline_rounded),
            iconSize: 26,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.sendLinkEvents;
    return Material(
      color: on ? AlpacaColors.preview : AlpacaColors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('send-link'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.setSendLinkEvents(!on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'Send link',
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.6,
              color: on ? const Color(0xFF172000) : AlpacaColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.followCues;
    return Material(
      color: on ? AlpacaColors.brass : AlpacaColors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('follow-cues'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.setFollowCues(!on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'Follow cues',
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.6,
              color: on ? const Color(0xFF1A1408) : AlpacaColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _MockBanner extends StatelessWidget {
  const _MockBanner({required this.controller, required this.text});

  final ConsoleController controller;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AlpacaColors.mock),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AlpacaColors.mock, fontSize: 13, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: controller.boot,
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }
}

class _StackedConsole extends StatefulWidget {
  const _StackedConsole({required this.controller});

  final ConsoleController controller;

  @override
  State<_StackedConsole> createState() => _StackedConsoleState();
}

class _StackedConsoleState extends State<_StackedConsole> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _TabButton(label: 'Switcher', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
              const SizedBox(width: 8),
              _TabButton(
                label: 'Presentation',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _tab == 0
                ? _SwitcherPane(controller: widget.controller)
                : _PresentationPane(controller: widget.controller),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AlpacaColors.panelRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AlpacaColors.brass : AlpacaColors.line),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitcherPane extends StatelessWidget {
  const _SwitcherPane({required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final program = controller.inputById(controller.programId);
    final preview = controller.inputById(controller.previewId);
    final linking = controller.switcherSide == LinkSide.connecting;
    return _Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('SWITCHER', style: AlpacaText.bus),
              const Spacer(),
              Text(
                controller.switcherSide == LinkSide.live ? controller.switcherNote : 'ME 1',
                style: AlpacaText.mono,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Tally(
                  key: const Key('program-tally'),
                  kicker: 'PROGRAM',
                  input: program,
                  color: AlpacaColors.program,
                  wash: AlpacaColors.programDeep,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Tally(
                  key: const Key('preview-tally'),
                  kicker: 'PREVIEW',
                  input: preview,
                  color: AlpacaColors.preview,
                  wash: AlpacaColors.previewDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              itemCount: controller.inputs.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 148,
                mainAxisExtent: 76,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final input = controller.inputs[index];
                final onProgram = input.id == controller.programId;
                final onPreview = input.id == controller.previewId;
                return _InputButton(
                  input: input,
                  onProgram: onProgram,
                  onPreview: onPreview,
                  enabled: !linking,
                  onTap: () => controller.selectPreview(input),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _ActionButton(
                  label: 'CUT',
                  color: AlpacaColors.program,
                  foreground: Colors.white,
                  enabled: !linking,
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    controller.cut();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _ActionButton(
                  label: 'AUTO',
                  color: controller.autoOffered ? AlpacaColors.brass : AlpacaColors.panelRaised,
                  foreground: controller.autoOffered ? const Color(0xFF1A1408) : AlpacaColors.muted,
                  enabled: !linking && controller.autoOffered,
                  caption: controller.autoOffered ? null : 'Auto is off for this bridge',
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    controller.take();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresentationPane extends StatelessWidget {
  const _PresentationPane({required this.controller});

  final ConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final playlist = controller.playlistById(controller.selectedPlaylistId);
    final linking = controller.presentationSide == LinkSide.connecting;
    final cueLine = controller.lastCue == null
        ? 'No cue yet'
        : 'Cue ${controller.lastCue} · ${controller.lastCueResult ?? ''}';
    return _Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('PRESENTATION', style: AlpacaText.bus),
              const Spacer(),
              Text(
                controller.presentationSide == LinkSide.mock ? 'MOCK' : controller.presentationNote,
                style: AlpacaText.mono.copyWith(
                  color: controller.presentationSide == LinkSide.mock
                      ? AlpacaColors.mock
                      : AlpacaColors.live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.playlists.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No playlists on this host.',
                  style: TextStyle(color: AlpacaColors.muted, fontSize: 16),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: controller.playlists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = controller.playlists[index];
                  final selected = item.id == controller.selectedPlaylistId;
                  return Material(
                    color: selected ? AlpacaColors.brass : AlpacaColors.panelRaised,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => controller.selectPlaylist(item.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selected ? const Color(0xFF1A1408) : AlpacaColors.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (controller.presentationSide == LinkSide.live &&
                controller.presentationWire == PresentationWire.http &&
                playlist != null)
              _SlideStrip(controller: controller, playlist: playlist),
            Expanded(
              child: playlist == null || playlist.items.isEmpty
                  ? const Center(
                      child: Text(
                        'This playlist has no items yet.',
                        style: TextStyle(color: AlpacaColors.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: playlist.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = playlist.items[index];
                        final active = item.index == controller.activeItemIndex;
                        return Material(
                          color: active ? const Color(0xFF2C2616) : AlpacaColors.panelRaised,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: linking
                                ? null
                                : () => controller.triggerIndex(playlist.id, item.index),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 64),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: active ? AlpacaColors.brass : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${item.index + 1}',
                                      style: AlpacaText.mono.copyWith(color: AlpacaColors.brass),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (active)
                                    const Text(
                                      'ON AIR',
                                      style: TextStyle(
                                        fontFamily: 'BarlowCondensed',
                                        color: AlpacaColors.brass,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
          const SizedBox(height: 8),
          Text(cueLine, style: AlpacaText.mono),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'PREV',
                  color: AlpacaColors.panelRaised,
                  foreground: AlpacaColors.text,
                  enabled: !linking,
                  onPressed: controller.previousItem,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'NEXT',
                  color: AlpacaColors.preview,
                  foreground: const Color(0xFF172000),
                  enabled: !linking,
                  onPressed: controller.nextItem,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'CLEAR',
                  color: AlpacaColors.programDeep,
                  foreground: AlpacaColors.program,
                  enabled: !linking,
                  onPressed: controller.clearSlide,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SlideStrip extends StatelessWidget {
  const _SlideStrip({required this.controller, required this.playlist});

  final ConsoleController controller;
  final ShowPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final item in playlist.items) {
      for (final slide in item.slides) {
        final bytes = slide.bytes;
        final selected = controller.activeItemIndex == item.index && controller.activeCueIndex == slide.index;
        cards.add(
          SizedBox(
            width: bytes == null ? 220 : 168,
            child: Material(
              color: AlpacaColors.panelRaised,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: ValueKey('slide-${item.index}-${slide.index}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => controller.triggerSlide(
                  playlistId: playlist.id,
                  itemIndex: item.index,
                  cueIndex: slide.index,
                  presentationUuid: item.presentationUuid,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AlpacaColors.brass : Colors.transparent),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: bytes == null
                            ? Text(
                                slide.missing ?? 'No slide image.',
                                style: const TextStyle(color: AlpacaColors.muted, fontSize: 11, height: 1.25),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.medium,
                                  semanticLabel: slide.label,
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        slide.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    if (cards.isEmpty) {
      if (!controller.slidesLoading) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Loading slide images from the host.',
          style: TextStyle(color: AlpacaColors.muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => cards[index],
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AlpacaColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AlpacaColors.line),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({
    super.key,
    required this.kicker,
    required this.input,
    required this.color,
    required this.wash,
  });

  final String kicker;
  final VideoInput input;
  final Color color;
  final Color wash;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(14),
        border: Border(top: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kicker, style: AlpacaText.bus.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(input.shortName, style: AlpacaText.tally),
          Text(
            input.longName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AlpacaColors.muted),
          ),
        ],
      ),
    );
  }
}

class _InputButton extends StatelessWidget {
  const _InputButton({
    required this.input,
    required this.onProgram,
    required this.onPreview,
    required this.enabled,
    required this.onTap,
  });

  final VideoInput input;
  final bool onProgram;
  final bool onPreview;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = onProgram
        ? AlpacaColors.program
        : onPreview
        ? AlpacaColors.preview
        : AlpacaColors.line;
    return Material(
      color: onPreview ? const Color(0xFF2A3118) : AlpacaColors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: onProgram || onPreview ? 2 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                input.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                onProgram ? 'PGM' : input.longName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: onProgram ? AlpacaColors.program : AlpacaColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.foreground,
    required this.enabled,
    required this.onPressed,
    this.caption,
  });

  final String label;
  final Color color;
  final Color foreground;
  final bool enabled;
  final VoidCallback onPressed;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Material(
        color: enabled ? color : AlpacaColors.panelRaised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AlpacaText.action.copyWith(color: enabled ? foreground : AlpacaColors.muted)),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AlpacaColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Tone { mock, live, brass, down }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      _Tone.mock => (AlpacaColors.mock, const Color(0xFF1A1408), AlpacaColors.mock),
      _Tone.live => (Colors.transparent, AlpacaColors.live, AlpacaColors.live),
      _Tone.brass => (Colors.transparent, AlpacaColors.brass, AlpacaColors.brass),
      _Tone.down => (Colors.transparent, AlpacaColors.down, AlpacaColors.down),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: foreground,
        ),
      ),
    );
  }
}

void _showLog(BuildContext context, ConsoleController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AlpacaColors.panel,
    builder: (context) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final lines = controller.eventLog;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Event log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(controller.linkNote, style: AlpacaText.mono),
                  const SizedBox(height: 8),
                  Expanded(
                    child: lines.isEmpty
                        ? const Text('No events yet.', style: TextStyle(color: AlpacaColors.muted))
                        : ListView.builder(
                            itemCount: lines.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(lines[index], style: AlpacaText.mono),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
