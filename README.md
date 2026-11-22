# Pocket XR for iPhone and iPad

In development, private until it works. The plan, with every Android feature and what iOS can match, is in
[docs/PLAN.md](docs/PLAN.md). What has and has not been proven is in [docs/STATUS.md](docs/STATUS.md).

## Layout

- `Sources/PocketXRCore`: the shared core (glasses, head tracking, control link, the Space's maths), copied from
  Pocket XR for Mac so both stay the same. `Tests/` and `Checks/` are its tests.
- `App/`: the iOS app. Phase 0 is a probe: a test picture on the glasses, and a report of what iOS lets the app reach.
- `Tools/FakeGlasses`: a stand-in for the glasses' sensor stream, for the Simulator.
- `project.yml`: the Xcode project, made with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Building

Needs a Mac with Xcode 26 (macOS Sequoia or later). CI on GitHub Actions does this on every push.

```bash
swift test                 # core tests
brew install xcodegen
xcodegen generate          # makes PocketXR.xcodeproj
open PocketXR.xcodeproj
```

In the Simulator, run `swift run FakeGlasses` on the Mac and launch the app with the arguments
`-PXRProbeHost 127.0.0.1` to see head tracking work against the fake stream.

## Licence

GPL-3.0, as Pocket XR on other platforms.

## Credits

PC screens use [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c) (Moonlight's stream core,
GPLv3, with its `enet` and `nanors` parts, MIT), in `Native/moonlight/moonlight-common-c`, unchanged. Pairing and the
stream's set-up follow Pocket XR for Windows, itself ported from moonlight-android's NvHTTP and PairingManager (GPLv3).
