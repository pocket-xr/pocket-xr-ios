# What is proven, and what is not

There is no iPhone or iPad to test on yet (21 Nov 2026), so everything is checked in CI on GitHub Actions
(macos-26 runner, Xcode 26.3, iOS 26.4.1 Simulator): builds, the core's tests, and runs in the iOS Simulator.

## Phase 0

| Item | How it is checked | State (CI run 44951769408, 21 Nov 2026) |
|---|---|---|
| Shared core compiles for iOS and its tests pass | `swift test`, core checks, device build | **Passes** |
| App builds for real iPhones and iPads (unsigned) | `xcodebuild -sdk iphoneos` | **Passes** |
| App runs in the Simulator | installs, launches, phone screenshot | **Passes**: the probe screen shows |
| Head tracking path (connect, framing, fusion, rate) | app in the Simulator reads Tools/FakeGlasses on 127.0.0.1:52998 for 12 s | **Passes**: 12,510 reports, about 1,000 a second, yaw follows the fake head turn (0 to 54.7°) |
| Glasses test picture draws at 1920x1080 and 3840x1080 | PNGs rendered by the app | **Passes**: picture, both eyes in 3840x1080, window moved by the head turn |
| External display scene | Simulator's I/O > External Displays > 1920×1080, by UI scripting | **Not proven.** The menu click works, but in two runs iOS never reported a new screen or offered the external display scene to the app (the app logs both), and `simctl io --display=external` timed out. Probably the headless runner's Simulator does not draw external displays. Needs a Simulator on a Mac with a screen, or a real device. |
| Signing and TestFlight upload | TestFlight workflow, after Mike's App Store Connect setup (docs/APPSTORE-SETUP.md) | Not yet run |

## Only a real device can prove

- That a USB-C iPhone or iPad shows Pocket XR's own picture on the glasses (rather than mirroring), at what size
  and refresh, and whether 3840x1080 is offered after the glasses switch to 3D.
- **Whether iOS brings up the glasses' USB network** (Aura and One family, 169.254.2.x) and lets the app reach
  TCP 52998. This decides head tracking, Steady mode and PC VR on iOS. Untested.
- The Local Network prompt for that link.
- Whether the picture stays on the glasses with the phone's screen blanked by the proximity sensor (Pocket mode).
- Anything about real glasses' head tracking quality, latency or stillness.

## CI minutes

The repo is private, so macOS runs count against the organisation's free 2,000 Actions minutes a month at 10x.
By 21 Nov 2026 this repo had used 47 macOS minutes (470 of the 2,000; $2.91 at list price, charged $0). Half of that
was one run stuck booting the Simulator before step timeouts were added. A normal run now takes about 4 to 5 minutes,
so roughly 30 more runs fit this month. With no payment method on the organisation, runs stop when the minutes are
used up; nothing is charged. Making the repo public makes them free.
