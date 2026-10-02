# Video Run

![Video Run](assets/brand/video-run-icon.png)

Video Run is a dense touch console for program and preview switching, and for playlist transport. Targets are Android and desktop. Live hardware is tried first. If a host does not answer, that bank stays on screen and is marked **MOCK**.

## Run

```bash
flutter pub get
flutter run -d linux
flutter run -d windows
flutter run -d macos
```

Android, arm64 debug package:

```bash
scripts/build_apk.sh
```

The script writes `dist/video-run-arm64-debug.apk`.

## Hardware links

### Switcher

The switcher link uses the ATEM UDP control protocol on port **9910**.

- Preview punch sends `CPvI` on mix effect 1.
- **CUT** sends `DCut`.
- **AUTO** sends `DAut` when **Send auto transitions** is on. Turn that off when a bridge only accepts a cut. The AUTO key then reads “Auto is off for this bridge”.
- Program and preview come back as `PrgI` and `PrvI`. Input names come back as `InPr`.
- The console opens with a random session id, answers the handshake, and acknowledges reliable packets. The first empty packet after the state dump is acknowledged with remote sequence `0x61`.
- If the host is quiet for about two seconds, the console drops to the labeled mock bank: six cameras, media, bars, and black.

Put the switcher’s LAN address in **Links**. Leave the host empty to stay in mock.

### Presentation

The presentation link speaks the ProPresenter HTTP API used by 7.9 and later. The port is the one shown in that app’s network settings, often **50001**.

| Action | Request |
| --- | --- |
| Playlist list | `GET /v1/playlists` |
| Playlist detail | `GET /v1/playlist/{id}` |
| Next | `GET /v1/trigger/next` |
| Previous | `GET /v1/trigger/previous` |
| Clear slide | `GET /v1/clear/layer/slide` |
| Trigger item | `GET /v1/playlist/{id}/{index}/trigger` |

An optional token is sent as `Authorization: Bearer …`. The host must allow cleartext HTTP. The Android package does.

**Legacy socket** is the older remote websocket at `ws://host:port/remote`. The console authenticates with protocol `701` and the remote password, then uses `playlistRequestAll`, `presentationTriggerNext`, `presentationTriggerPrevious`, and `clearAll`.

A dead host, a refused password, or a non-JSON body leaves the error on screen and restores the mock playlists.

## Alpaca Link

Alpaca Link is the LAN protocol. It is not the product name. Each event is one UTF-8 JSON object in a UDP datagram.

Video Run joins multicast **239.255.42.77** port **44771** and sends with TTL **1**. It does not use broadcast unless **Broadcast fallback** is on. That flag also sends the same datagram to `255.255.255.255:44771`. Both the flag and every follow/send control start **off**.

Datagrams whose `source.app` is `video-run` are dropped, including this console’s own multicast loop, so a send cannot run the cue map again.

Envelope:

```json
{
  "version": 1,
  "source": { "app": "video-run", "instance": "8f1c0c2e-6b4a-4e1d-9c3a-1b2d3e4f5061", "name": "Video Run" },
  "type": "video.cut",
  "name": "cam-2",
  "payload": { "input": 2, "label": "Cam 2", "me": 0 },
  "timestamp": "2026-10-02T22:40:00.000Z",
  "id": "3c2b1a09-8877-4665-9abc-def012345678",
  "show": ""
}
```

| Field | Meaning |
| --- | --- |
| `version` | Protocol version. This console speaks `1` and ignores other versions. |
| `source.app` | Sending application. Video Run always writes `video-run` and ignores that value on input. |
| `source.instance` | Stable id for this process, generated once and kept in settings. |
| `source.name` | Operator-facing name. The default is `Video Run`. |
| `type` | Event type. `video.cut` and `cue.fire` are the required types. AUTO sends `video.take` when send is on. |
| `name` | Short name. For a cut or take this is the source slug, such as `cam-2`. For a cue it is the cue name. |
| `payload` | Object of extra fields. A missing payload is treated as `{}`. |
| `timestamp` | UTC time in ISO-8601. |
| `id` | Unique id for this datagram. A repeated id is ignored. |
| `show` | Show name, or an empty string when none is set. |

A cue from another application:

```json
{
  "version": 1,
  "source": { "app": "show-cues", "instance": "cue-desk-1", "name": "Cue desk" },
  "type": "cue.fire",
  "name": "wide",
  "payload": {},
  "timestamp": "2026-10-02T22:41:00.000Z",
  "id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "show": "Sunday"
}
```

Cue names match without case sensitivity.

### Follow cues and send

**Follow cues** and **Send link** are off until you turn them on.

While Follow cues is on, a `cue.fire` from another `source.app` whose `name` is in the cue map runs that action: cut to an input, preview an input, auto take, presentation next, previous, clear slide, or trigger a playlist item. While it is off, the cue is logged and left alone.

While Send link is off, cuts, autos, and Fire stay on this console and are not written to the network. While it is on, CUT emits `video.cut`, AUTO emits `video.take`, and Fire emits `cue.fire`.

**Load rehearsal map** writes four names: `wide`, `close`, `lyrics`, and `clear-slide`. **Fire** runs that name locally. It is also sent only when Send link is on.

## Tests

```bash
flutter test
```
