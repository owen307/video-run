import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/console_models.dart';
import '../state/console_controller.dart';
import '../theme/alpaca_theme.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.controller});

  final ConsoleController controller;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late final TextEditingController _switcherHost;
  late final TextEditingController _switcherPort;
  late final TextEditingController _presentationHost;
  late final TextEditingController _presentationPort;
  late final TextEditingController _secret;
  late final TextEditingController _sourceName;
  late final TextEditingController _showName;
  late final TextEditingController _cueName;
  late bool _autoEnabled;
  late PresentationWire _wire;
  CueActionKind _kind = CueActionKind.cutToInput;
  int? _inputId;
  String? _playlistId;
  int? _itemIndex;

  ConsoleController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _switcherHost = TextEditingController(text: controller.switcherHost);
    _switcherPort = TextEditingController(text: '${controller.switcherPort}');
    _presentationHost = TextEditingController(text: controller.presentationHost);
    _presentationPort = TextEditingController(text: '${controller.presentationPort}');
    _secret = TextEditingController(text: controller.presentationSecret);
    _sourceName = TextEditingController(text: controller.sourceName);
    _showName = TextEditingController(text: controller.showName);
    _cueName = TextEditingController();
    _autoEnabled = controller.autoEnabled;
    _wire = controller.presentationWire;
    _inputId = controller.inputs.isEmpty ? null : controller.inputs.first.id;
    _playlistId = controller.playlists.isEmpty ? null : controller.playlists.first.id;
    _itemIndex = controller.playlists.isEmpty || controller.playlists.first.items.isEmpty
        ? null
        : controller.playlists.first.items.first.index;
  }

  @override
  void dispose() {
    _switcherHost.dispose();
    _switcherPort.dispose();
    _presentationHost.dispose();
    _presentationPort.dispose();
    _secret.dispose();
    _sourceName.dispose();
    _showName.dispose();
    _cueName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlpacaColors.ink,
      appBar: AppBar(
        backgroundColor: AlpacaColors.ink,
        foregroundColor: AlpacaColors.text,
        title: const Text('Links'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    const _SectionLabel('Switcher'),
                    TextField(
                      controller: _switcherHost,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        helperText: 'UDP 9910. Leave empty to rehearse on the mock bank.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _switcherPort,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send auto transitions'),
                      subtitle: const Text('Turn this off when the bridge only accepts a cut.'),
                      value: _autoEnabled,
                      onChanged: (value) => setState(() => _autoEnabled = value),
                    ),
                    const _SectionLabel('Presentation'),
                    TextField(
                      controller: _presentationHost,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        helperText: 'HTTP API, often port 50001. Empty stays on the mock playlists.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _presentationPort,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<PresentationWire>(
                      segments: const [
                        ButtonSegment(value: PresentationWire.http, label: Text('HTTP API')),
                        ButtonSegment(value: PresentationWire.legacy, label: Text('Legacy socket')),
                      ],
                      selected: {_wire},
                      onSelectionChanged: (value) => setState(() => _wire = value.first),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _secret,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Token or remote password',
                        helperText: 'Optional. Sent as a bearer token on HTTP, or as the remote password on the legacy socket.',
                      ),
                    ),
                    const _SectionLabel('Link'),
                    TextField(
                      controller: _sourceName,
                      decoration: const InputDecoration(
                        labelText: 'Source name',
                        helperText: 'Stored as source.name. The app id stays video-run.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _showName,
                      decoration: const InputDecoration(
                        labelText: 'Show',
                        helperText: 'Copied into the show field. Leave empty when no show is open.',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send link events'),
                      subtitle: const Text('Off until you enable it. Cuts and cues stay on this console.'),
                      value: controller.sendLinkEvents,
                      onChanged: (value) {
                        controller.setSendLinkEvents(value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Broadcast fallback'),
                      subtitle: const Text('Also send to 255.255.255.255. Off unless this network cannot hear multicast.'),
                      value: controller.broadcastFallback,
                      onChanged: (value) {
                        controller.setBroadcastFallback(value);
                      },
                    ),
                    const _SectionLabel('Cue map'),
                    const Text(
                      'Follow cues, on the console, runs one of these when a cue.fire arrives with the same name.',
                      style: TextStyle(color: AlpacaColors.muted, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    if (controller.cues.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No cue names mapped. Incoming cues are shown and left alone.',
                          style: TextStyle(color: AlpacaColors.muted),
                        ),
                      ),
                    for (final cue in controller.cues) _CueRow(controller: controller, cue: cue),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cueName,
                      decoration: const InputDecoration(labelText: 'Cue name'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<CueActionKind>(
                      initialValue: _kind,
                      decoration: const InputDecoration(labelText: 'Action'),
                      items: const [
                        DropdownMenuItem(value: CueActionKind.cutToInput, child: Text('Cut to input')),
                        DropdownMenuItem(value: CueActionKind.previewInput, child: Text('Preview input')),
                        DropdownMenuItem(value: CueActionKind.take, child: Text('Auto take')),
                        DropdownMenuItem(value: CueActionKind.next, child: Text('Presentation next')),
                        DropdownMenuItem(value: CueActionKind.previous, child: Text('Presentation previous')),
                        DropdownMenuItem(value: CueActionKind.clear, child: Text('Clear slide')),
                        DropdownMenuItem(value: CueActionKind.triggerItem, child: Text('Trigger playlist item')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _kind = value);
                      },
                    ),
                    if (_kind == CueActionKind.cutToInput || _kind == CueActionKind.previewInput) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _inputId,
                        decoration: const InputDecoration(labelText: 'Input'),
                        items: [
                          for (final input in controller.inputs)
                            DropdownMenuItem(value: input.id, child: Text(input.longName)),
                        ],
                        onChanged: (value) => setState(() => _inputId = value),
                      ),
                    ],
                    if (_kind == CueActionKind.triggerItem) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _playlistId,
                        decoration: const InputDecoration(labelText: 'Playlist'),
                        items: [
                          for (final playlist in controller.playlists)
                            DropdownMenuItem(value: playlist.id, child: Text(playlist.name)),
                        ],
                        onChanged: (value) => setState(() {
                          _playlistId = value;
                          final playlist = controller.playlistById(value);
                          _itemIndex = playlist == null || playlist.items.isEmpty
                              ? null
                              : playlist.items.first.index;
                        }),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _itemIndex,
                        decoration: const InputDecoration(labelText: 'Item'),
                        items: [
                          for (final item in controller.playlistById(_playlistId)?.items ?? const <ShowItem>[])
                            DropdownMenuItem(value: item.index, child: Text(item.name)),
                        ],
                        onChanged: (value) => setState(() => _itemIndex = value),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () {
                          final name = _cueName.text.trim();
                          if (name.isEmpty) return;
                          controller.addCue(
                            CueBinding(
                              cueName: name,
                              kind: _kind,
                              inputId: _kind == CueActionKind.cutToInput || _kind == CueActionKind.previewInput
                                  ? _inputId
                                  : null,
                              playlistId: _kind == CueActionKind.triggerItem ? _playlistId : null,
                              itemIndex: _kind == CueActionKind.triggerItem ? _itemIndex : null,
                            ),
                          );
                          _cueName.clear();
                        },
                        child: const Text('Add cue'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: TextButton(
                        onPressed: controller.loadRehearsalMap,
                        child: const Text('Load rehearsal map'),
                      ),
                    ),
                    const Text(
                      'Replaces the map with wide, close, lyrics, and clear-slide.',
                      style: TextStyle(color: AlpacaColors.muted, fontSize: 13),
                    ),
                    const _SectionLabel('Connection notes'),
                    const Text(
                      'The switcher link speaks the UDP control protocol on port 9910. Preview selects the preview bus, CUT sends a cut, and AUTO sends an auto transition on mix effect 1 when that command is enabled. A silent host drops this console into the labeled mock bank.\n\n'
                      'The presentation link calls the HTTP API for the playlist list, next, previous, and clear-slide. Older hosts can use the legacy remote socket instead. A refused password or a non-JSON reply stays on screen as the error, and the playlists fall back to mock.\n\n'
                      'The LAN link joins multicast 239.255.42.77 port 44771 with TTL 1. Send link events and Follow cues start off. Broadcast to 255.255.255.255 is used only when Broadcast fallback is on. Events whose source.app is video-run are ignored, so this console cannot loop its own messages. The field list is in the README.',
                      style: TextStyle(height: 1.4, color: AlpacaColors.text),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text(
                      'Apply and link',
                      style: TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _apply() async {
    await controller.applyConnections(
      switcherHost: _switcherHost.text,
      switcherPort: int.tryParse(_switcherPort.text) ?? 9910,
      autoEnabled: _autoEnabled,
      presentationHost: _presentationHost.text,
      presentationPort: int.tryParse(_presentationPort.text) ?? 50001,
      wire: _wire,
      secret: _secret.text,
      sourceName: _sourceName.text,
      showName: _showName.text,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'BarlowCondensed',
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
          color: AlpacaColors.brass,
        ),
      ),
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({required this.controller, required this.cue});

  final ConsoleController controller;
  final CueBinding cue;

  @override
  Widget build(BuildContext context) {
    final label = cueActionLabel(
      cue,
      inputName: (id) => controller.inputById(id).longName,
      playlistName: (id) => controller.playlistById(id)?.name ?? id,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AlpacaColors.panel,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cue.cueName, style: AlpacaText.mono.copyWith(color: AlpacaColors.text)),
                    Text(label, style: const TextStyle(color: AlpacaColors.muted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => controller.fireCue(cue.cueName),
                child: const Text('Fire'),
              ),
              IconButton(
                onPressed: () => controller.removeCue(cue.cueName),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
