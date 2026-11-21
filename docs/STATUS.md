# What is proven, and what is not

Updated with each change. There is no iPhone or iPad to test on yet (21 Nov 2026), so everything is checked in CI
on GitHub Actions: builds, the core's tests, and runs in the iOS Simulator.

## Phase 0

| Item | How it is checked | State |
|---|---|---|
| Shared core compiles for iOS and its tests pass | CI: `swift test`, core checks, device build | see the latest CI run |
| App builds for real iPhones and iPads (unsigned) | CI: `xcodebuild -sdk iphoneos` | see the latest CI run |
| App runs in the Simulator | CI: installs, launches, phone screenshot | see the latest CI run |
| Head tracking path (connect, framing, fusion, rate) | CI: app in the Simulator reads Tools/FakeGlasses on 127.0.0.1:52998 | see the latest CI run |
| Glasses test picture draws at 1920x1080 and 3840x1080 | CI: PNGs rendered by the app | see the latest CI run |
| External display scene in the Simulator | CI: Simulator's I/O > External Displays, if the runner allows scripting it | see the latest CI run |
| Signing and TestFlight upload | TestFlight workflow, after Mike's App Store Connect setup | not yet run |

## Only a real device can prove

- That a USB-C iPhone or iPad shows Pocket XR's own picture on the glasses (rather than mirroring), at what size
  and refresh, and whether 3840x1080 is offered after the glasses switch to 3D.
- **Whether iOS brings up the glasses' USB network** (Aura and One family, 169.254.2.x) and lets the app reach
  TCP 52998. This decides head tracking, Steady mode and PC VR on iOS. Untested.
- The Local Network prompt for that link.
- Whether the picture stays on the glasses with the phone's screen blanked by the proximity sensor (Pocket mode).
- Anything about real glasses' head tracking quality, latency or stillness.
