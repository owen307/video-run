# Video Run

Video Run is a dense touch console for program and preview switching, and for playlist transport. Targets are Android and desktop. Live hardware is tried first. If a host does not answer, that bank stays on screen and is marked **MOCK**.

Source was not pushed from this environment: `gh` is not logged in, and `git push` to GitHub has no credentials. Release **v0.1.0** was not published. The arm64 debug APK is `dist/video-run-arm64-debug.apk` from `scripts/build_apk.sh`.

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

## Alpaca Link

Alpaca Link is the LAN protocol. It is not the product name. Each event is one UTF-8 JSON object in a UDP datagram.

Video Run joins multicast **239.255.42.77** port **44771** and sends with TTL **1**. It does not use broadcast unless **Broadcast fallback** is on. That flag also sends the same datagram to `255.255.255.255:44771`. Both the flag and every follow/send control start **off**.

Datagrams whose `source.app` is `video-run` are dropped.

Envelope fields: `version`, `source.app`, `source.instance`, `source.name`, `type`, `name`, `payload`, `timestamp`, `id`, `show`. Types include `video.cut` and `cue.fire`. AUTO sends `video.take` when send is on.
