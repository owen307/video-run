import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/console_models.dart';
import '../protocol/alpaca_link.dart';
import '../protocol/atem_client.dart';
import '../protocol/presentation_client.dart';

class ConsoleController extends ChangeNotifier {
  ConsoleController({
    LinkPort? link,
    AtemClient? switcher,
    PresentationClient? presentation,
    SharedPreferences? preferences,
  }) : _link = link ?? AlpacaLink(),
       _switcher = switcher ?? AtemClient(),
       _presentation = presentation ?? PresentationClient() {
    _preferences = preferences;
    inputs = mockInputs();
    playlists = mockPlaylists();
    programId = 1;
    previewId = 2;
    selectedPlaylistId = playlists.first.id;
    activeItemIndex = 0;
  }

  static const _prefsKey = 'video_run_settings_v1';

  final LinkPort _link;
  final AtemClient _switcher;
  final PresentationClient _presentation;
  SharedPreferences? _preferences;

  LinkSide switcherSide = LinkSide.mock;
  LinkSide presentationSide = LinkSide.mock;
  String switcherNote = 'No switcher address yet';
  String presentationNote = 'No presentation address yet';
  String? productName;
  bool autoEnabled = true;
  bool followCues = false;
  bool sendLinkEvents = false;
  bool broadcastFallback = false;
  List<CueBinding> cues = [];
  late List<VideoInput> inputs;
  int? programId;
  int? previewId;
  late List<ShowPlaylist> playlists;
  String? selectedPlaylistId;
  int? activeItemIndex;
  String linkNote = 'Link starting';
  final List<String> eventLog = [];
  String? lastCue;
  String? lastCueResult;

  String switcherHost = '';
  int switcherPort = 9910;
  String presentationHost = '';
  int presentationPort = 50001;
  PresentationWire presentationWire = PresentationWire.http;
  String presentationSecret = '';
  String sourceName = 'Video Run';
  String showName = '';
  String _instanceId = '';

  bool get autoOffered =>
      autoEnabled && (switcherSide != LinkSide.live || _switcher.autoAvailable);

  StreamSubscription<AtemSnapshot>? _switcherSub;
  StreamSubscription<LinkEnvelope>? _linkSub;
  int _generation = 0;
  bool _disposed = false;
  String? _lastCueKey;
  DateTime? _lastCueAt;

  Future<void> boot() async {
    final prefs = await _prefs();
    _load(prefs);
    if (_instanceId.isEmpty) _instanceId = newLinkId();
    _notify();
    await _persist();
    await _openLink();
    await _linkHardware();
  }

  Future<void> applyConnections({
    required String switcherHost,
    required int switcherPort,
    required bool autoEnabled,
    required String presentationHost,
    required int presentationPort,
    required PresentationWire wire,
    required String secret,
    required String sourceName,
    required String showName,
  }) async {
    this.switcherHost = switcherHost.trim();
    this.switcherPort = switcherPort;
    this.autoEnabled = autoEnabled;
    this.presentationHost = presentationHost.trim();
    this.presentationPort = presentationPort;
    presentationWire = wire;
    presentationSecret = secret.trim();
    this.sourceName = sourceName.trim().isEmpty ? 'Video Run' : sourceName.trim();
    this.showName = showName.trim();
    if (_instanceId.isEmpty) _instanceId = newLinkId();
    await _persist();
    _notify();
    await _openLink();
    await _linkHardware();
  }

  Future<void> setFollowCues(bool value) async {
    followCues = value;
    _notify();
    await _persist();
  }

  Future<void> setSendLinkEvents(bool value) async {
    sendLinkEvents = value;
    _notify();
    await _persist();
  }

  Future<void> setBroadcastFallback(bool value) async {
    broadcastFallback = value;
    _syncLinkConfig();
    _notify();
    await _persist();
  }

  Future<void> addCue(CueBinding binding) async {
    final name = binding.cueName.trim();
    if (name.isEmpty) return;
    cues = [
      for (final cue in cues)
        if (cue.cueName.trim().toLowerCase() != name.toLowerCase()) cue,
      CueBinding(
        cueName: name,
        kind: binding.kind,
        inputId: binding.inputId,
        playlistId: binding.playlistId,
        itemIndex: binding.itemIndex,
      ),
    ];
    _notify();
    await _persist();
  }

  Future<void> removeCue(String cueName) async {
    cues = [
      for (final cue in cues)
        if (cue.cueName.trim().toLowerCase() != cueName.trim().toLowerCase()) cue,
    ];
    _notify();
    await _persist();
  }

  Future<void> loadRehearsalMap() async {
    final first = inputs.isNotEmpty ? inputs.first.id : 1;
    final second = inputs.length > 1 ? inputs[1].id : first;
    cues = [
      CueBinding(cueName: 'wide', kind: CueActionKind.cutToInput, inputId: first),
      CueBinding(cueName: 'close', kind: CueActionKind.cutToInput, inputId: second),
      const CueBinding(cueName: 'lyrics', kind: CueActionKind.next),
      const CueBinding(cueName: 'clear-slide', kind: CueActionKind.clear),
    ];
    _notify();
    await _persist();
  }

  Future<void> fireCue(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _handleCue(trimmed);
    _emitLink(type: 'cue.fire', name: trimmed, payload: const {});
  }

  Future<void> selectPreview(VideoInput input) async {
    if (switcherSide == LinkSide.connecting) return;
    previewId = input.id;
    _notify();
    if (switcherSide != LinkSide.live) return;
    try {
      await _switcher.setPreview(input.id);
    } on AtemLinkException catch (error) {
      _pushLog('Preview failed: $error');
    }
  }

  Future<void> cut() => _transition(auto: false);

  Future<void> take() => _transition(auto: true);

  Future<void> nextItem() => _transport(1);

  Future<void> previousItem() => _transport(-1);

  Future<void> clearSlide() async {
    if (presentationSide == LinkSide.connecting) return;
    activeItemIndex = null;
    _notify();
    if (presentationSide == LinkSide.live) {
      try {
        await _presentation.clear();
      } on PresentationException catch (error) {
        _pushLog('Clear failed: $error');
        return;
      }
    }
    _pushLog('Cleared slide');
  }

  Future<void> selectPlaylist(String id) async {
    selectedPlaylistId = id;
    final playlist = _playlistById(id);
    activeItemIndex = playlist == null || playlist.items.isEmpty ? null : playlist.items.first.index;
    _notify();
    if (playlist == null ||
        playlist.items.isNotEmpty ||
        presentationSide != LinkSide.live ||
        presentationWire != PresentationWire.http) {
      return;
    }
    try {
      final detailed = await _presentation.fetchDetail(id);
      playlists = [
        for (final item in playlists)
          if (item.id == id) detailed else item,
      ];
      _notify();
    } on PresentationException catch (error) {
      _pushLog('Playlist failed: $error');
    }
  }

  Future<void> triggerIndex(String playlistId, int index) async {
    selectedPlaylistId = playlistId;
    activeItemIndex = index;
    _notify();
    if (presentationSide != LinkSide.live) {
      _pushLog('Triggered item ${index + 1}');
      return;
    }
    final playlist = _playlistById(playlistId);
    ShowItem? item;
    if (playlist != null) {
      for (final candidate in playlist.items) {
        if (candidate.index == index) item = candidate;
      }
    }
    try {
      await _presentation.trigger(
        playlistId: playlistId,
        index: index,
        path: item?.triggerPath,
      );
      _pushLog('Triggered item ${index + 1}');
    } on PresentationException catch (error) {
      _pushLog('Trigger failed: $error');
    }
  }

  VideoInput inputById(int? id) {
    if (id == null) {
      return const VideoInput(id: -1, longName: '—', shortName: '—');
    }
    for (final input in inputs) {
      if (input.id == id) return input;
    }
    return VideoInput(
      id: id,
      longName: describeSource(id),
      shortName: shortSource(id),
    );
  }

  ShowPlaylist? playlistById(String? id) => _playlistById(id);

  @override
  void dispose() {
    _disposed = true;
    _switcherSub?.cancel();
    _linkSub?.cancel();
    _switcher.dispose();
    _presentation.dispose();
    final link = _link;
    if (link is AlpacaLink) {
      link.dispose();
    } else {
      link.stop();
    }
    super.dispose();
  }

  Future<void> _transition({required bool auto}) async {
    if (switcherSide == LinkSide.connecting) return;
    if (auto && !autoOffered) {
      _pushLog('Auto is off for this bridge');
      return;
    }
    final source = inputById(previewId);
    if (source.id < 0) {
      _pushLog('Nothing is on preview');
      return;
    }
    final previousProgram = programId;
    programId = source.id;
    previewId = previousProgram;
    _notify();
    if (switcherSide == LinkSide.live) {
      try {
        if (auto) {
          await _switcher.auto();
        } else {
          await _switcher.cut();
        }
      } on AtemLinkException catch (error) {
        programId = previousProgram;
        previewId = source.id;
        _pushLog('${auto ? 'Auto' : 'Cut'} failed: $error');
        _notify();
        return;
      }
    }
    _emitSwitch(auto ? 'video.take' : 'video.cut', source, auto: auto);
  }

  Future<void> _cutTo(VideoInput input) async {
    if (switcherSide == LinkSide.connecting) return;
    programId = input.id;
    _notify();
    if (switcherSide == LinkSide.live) {
      try {
        await _switcher.setProgram(input.id);
      } on AtemLinkException catch (error) {
        _pushLog('Cut failed: $error');
        return;
      }
    }
    _emitSwitch('video.cut', input, auto: false);
  }

  Future<void> _transport(int delta) async {
    if (presentationSide == LinkSide.connecting) return;
    final playlist = _playlistById(selectedPlaylistId);
    if (playlist != null && playlist.items.isNotEmpty) {
      final indexes = playlist.items.map((item) => item.index).toList();
      final current = activeItemIndex ?? indexes.first;
      final position = indexes.indexOf(current);
      final nextPosition = position < 0 ? 0 : (position + delta).clamp(0, indexes.length - 1);
      activeItemIndex = indexes[nextPosition];
      _notify();
    }
    if (presentationSide != LinkSide.live) {
      _pushLog(delta > 0 ? 'Presentation next' : 'Presentation previous');
      return;
    }
    try {
      if (delta > 0) {
        await _presentation.next();
      } else {
        await _presentation.previous();
      }
      _pushLog(delta > 0 ? 'Presentation next' : 'Presentation previous');
    } on PresentationException catch (error) {
      _pushLog('Transport failed: $error');
    }
  }

  void _emitSwitch(String type, VideoInput source, {required bool auto}) {
    _emitLink(
      type: type,
      name: source.slug,
      payload: {
        'input': source.id,
        'label': source.longName,
        'me': 0,
        if (auto) 'transition': 'auto',
      },
    );
  }

  void _emitLink({
    required String type,
    required String name,
    required Map<String, dynamic> payload,
  }) {
    if (!sendLinkEvents) {
      _pushLog('$type $name · send off');
      return;
    }
    if (_link.boundPort == null) {
      _pushLog('$type $name · link down');
      return;
    }
    _syncLinkConfig();
    _link.emit(type: type, name: name, payload: payload);
    _pushLog('$type $name');
  }

  void _syncLinkConfig() {
    _link.configure(
      instance: _instanceId,
      sourceName: sourceName,
      show: showName,
      broadcastFallback: broadcastFallback,
    );
  }

  Future<void> _openLink() async {
    await _linkSub?.cancel();
    if (_instanceId.isEmpty) _instanceId = newLinkId();
    _syncLinkConfig();
    await _link.start(broadcastFallback: broadcastFallback);
    if (_link.boundPort != null) {
      linkNote = 'Listening on $alpacaLinkGroup:$alpacaLinkPort';
    } else {
      linkNote = _link.lastError ?? 'Link is down';
    }
    _linkSub = _link.incoming.listen(_onLink);
    _notify();
  }

  Future<void> _linkHardware() async {
    final generation = ++_generation;
    await _linkSwitcher(generation);
    if (generation != _generation || _disposed) return;
    await _linkPresentation(generation);
  }

  Future<void> _linkSwitcher(int generation) async {
    await _switcherSub?.cancel();
    final host = switcherHost.trim();
    if (host.isEmpty) {
      _useMockSwitcher('No switcher address yet');
      return;
    }
    switcherSide = LinkSide.connecting;
    switcherNote = 'Linking to $host:$switcherPort';
    _notify();
    try {
      _switcherSub = _switcher.snapshots.listen(_onSwitcherSnapshot);
      await _switcher.connect(host, switcherPort);
      if (generation != _generation || _disposed) return;
      switcherSide = LinkSide.live;
      productName = _switcher.snapshot.productName;
      switcherNote = productName == null || productName!.isEmpty
          ? 'Live · $host:$switcherPort'
          : 'Live · $productName';
      _onSwitcherSnapshot(_switcher.snapshot);
      if (inputs.isEmpty || inputs.every((input) => input.longName.startsWith('Input '))) {
        inputs = fallbackLiveInputs();
        switcherNote = 'Live · $host · input names not announced yet';
      }
      _notify();
    } on AtemLinkException catch (error) {
      if (generation != _generation || _disposed) return;
      _useMockSwitcher(error.message);
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _useMockSwitcher('No reply from $host:$switcherPort');
    }
  }

  Future<void> _linkPresentation(int generation) async {
    final host = presentationHost.trim();
    if (host.isEmpty) {
      _useMockPresentation('No presentation address yet');
      return;
    }
    presentationSide = LinkSide.connecting;
    presentationNote = 'Linking to $host:$presentationPort';
    _notify();
    try {
      final lists = await _presentation.connect(
        host: host,
        port: presentationPort,
        wire: presentationWire,
        secret: presentationSecret,
      );
      if (generation != _generation || _disposed) return;
      presentationSide = LinkSide.live;
      playlists = lists;
      selectedPlaylistId = lists.isEmpty ? null : lists.first.id;
      activeItemIndex = lists.isEmpty || lists.first.items.isEmpty
          ? null
          : lists.first.items.first.index;
      presentationNote = 'Live · $host:$presentationPort';
      _notify();
    } on PresentationException catch (error) {
      if (generation != _generation || _disposed) return;
      _useMockPresentation(error.message);
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _useMockPresentation('Presentation host did not answer at $host:$presentationPort');
    }
  }

  void _useMockSwitcher(String reason) {
    switcherSide = LinkSide.mock;
    switcherNote = reason;
    productName = null;
    inputs = mockInputs();
    programId = 1;
    previewId = 2;
    _notify();
  }

  void _useMockPresentation(String reason) {
    presentationSide = LinkSide.mock;
    presentationNote = reason;
    playlists = mockPlaylists();
    selectedPlaylistId = playlists.first.id;
    activeItemIndex = 0;
    _notify();
  }

  void _onSwitcherSnapshot(AtemSnapshot snapshot) {
    if (switcherSide != LinkSide.live || _disposed) return;
    if (snapshot.inputs.isNotEmpty) {
      inputs = [...snapshot.inputs]
        ..sort((a, b) => sourceRank(a.id).compareTo(sourceRank(b.id)));
    }
    if (snapshot.programId != null) programId = snapshot.programId;
    if (snapshot.previewId != null) previewId = snapshot.previewId;
    if (snapshot.productName != null && snapshot.productName!.isNotEmpty) {
      productName = snapshot.productName;
      switcherNote = 'Live · $productName';
    }
    _notify();
  }

  Future<void> _onLink(LinkEnvelope envelope) async {
    if (envelope.version != linkVersion || _disposed) return;
    if (envelope.source.app == linkAppId) return;
    if (envelope.id == _lastCueKey) return;
    _lastCueKey = envelope.id;
    if (envelope.type != 'cue.fire') {
      _pushLog('${envelope.type} from ${envelope.source.app} (${envelope.name})');
      return;
    }
    await _handleCue(envelope.name);
  }

  Future<void> _handleCue(String name) async {
    if (_disposed || name.isEmpty) return;
    final now = DateTime.now();
    if (_lastCueAt != null &&
        lastCue == name &&
        now.difference(_lastCueAt!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastCueAt = now;
    lastCue = name;
    if (!followCues) {
      lastCueResult = 'Follow is off';
      _pushLog('cue.fire $name · follow off');
      return;
    }
    final binding = matchCue(cues, name);
    if (binding == null) {
      lastCueResult = 'No map';
      _pushLog('cue.fire $name · no map');
      return;
    }
    await _runBinding(binding);
    if (_disposed) return;
    lastCueResult = 'Followed';
    _pushLog('cue.fire $name · followed');
  }

  Future<void> _runBinding(CueBinding binding) async {
    switch (binding.kind) {
      case CueActionKind.cutToInput:
        final id = binding.inputId;
        if (id == null) return;
        await _cutTo(inputById(id));
      case CueActionKind.previewInput:
        final id = binding.inputId;
        if (id == null) return;
        await selectPreview(inputById(id));
      case CueActionKind.take:
        await take();
      case CueActionKind.next:
        await nextItem();
      case CueActionKind.previous:
        await previousItem();
      case CueActionKind.clear:
        await clearSlide();
      case CueActionKind.triggerItem:
        final playlistId = binding.playlistId;
        final index = binding.itemIndex;
        if (playlistId == null || index == null) return;
        await triggerIndex(playlistId, index);
    }
  }

  ShowPlaylist? _playlistById(String? id) {
    if (id == null) return null;
    for (final playlist in playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  void _pushLog(String line) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    eventLog.insert(0, '$stamp  $line');
    if (eventLog.length > 40) eventLog.removeLast();
    _notify();
  }

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  void _load(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      switcherHost = decoded['switcherHost'] as String? ?? switcherHost;
      switcherPort = _int(decoded['switcherPort']) ?? switcherPort;
      autoEnabled = decoded['autoEnabled'] as bool? ?? autoEnabled;
      presentationHost = decoded['presentationHost'] as String? ?? presentationHost;
      presentationPort = _int(decoded['presentationPort']) ?? presentationPort;
      presentationWire = decoded['presentationWire'] == 'legacy'
          ? PresentationWire.legacy
          : PresentationWire.http;
      presentationSecret = decoded['presentationSecret'] as String? ?? '';
      final storedName = decoded['sourceName'];
      if (storedName is String && storedName.trim().isNotEmpty) {
        sourceName = storedName.trim();
      }
      showName = decoded['showName'] as String? ?? '';
      final storedInstance = decoded['sourceInstance'];
      if (storedInstance is String && storedInstance.trim().isNotEmpty) {
        _instanceId = storedInstance.trim();
      }
      followCues = decoded['followCues'] as bool? ?? false;
      sendLinkEvents = decoded['sendLinkEvents'] as bool? ?? false;
      broadcastFallback = decoded['broadcastFallback'] as bool? ?? false;
      final storedCues = decoded['cues'];
      if (storedCues is List) {
        cues = [
          for (final entry in storedCues)
            if (entry is Map)
              ?CueBinding.fromJson(entry.map((key, value) => MapEntry('$key', value))),
        ];
      }
    } catch (_) {
      // Keep the in-memory rehearsal bank when stored settings are unreadable.
    }
  }

  Future<void> _persist() async {
    final prefs = await _prefs();
    if (_disposed) return;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'switcherHost': switcherHost,
        'switcherPort': switcherPort,
        'autoEnabled': autoEnabled,
        'presentationHost': presentationHost,
        'presentationPort': presentationPort,
        'presentationWire': presentationWire.name,
        'presentationSecret': presentationSecret,
        'sourceName': sourceName,
        'sourceInstance': _instanceId,
        'showName': showName,
        'followCues': followCues,
        'sendLinkEvents': sendLinkEvents,
        'broadcastFallback': broadcastFallback,
        'cues': [for (final cue in cues) cue.toJson()],
      }),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
