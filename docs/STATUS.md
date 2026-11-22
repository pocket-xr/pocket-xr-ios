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

## Phase 1 (started 22 Nov 2026): the Space

Checked in CI run 44970048573 (22 Nov 2026) on the iOS 26.4.1 Simulator, with no glasses (screenshot: phase1-simulator.png): the Space draws on the
phone as a preview, and a self-test (App/SpaceSelfTest.swift) drives it the way the trackpad does and reads the
results back from the pages themselves.

| Item | State |
|---|---|
| Window model: open beside others, move, resize, push and pull, bend, snap, arrange, Adjust all, Lock screens, focus order, save and load | **Passes** the core checks (Checks/WindowChecks.swift, over 1,100 checks in all) |
| Windows drawn in 3D from the head pose (Core Animation, live views) | **Seen** in the Simulator preview: two test pages and the launcher in perspective, the pointer on a page |
| Click on a web page through the pointer | **Passes**: the page's button reports "clicked 1" |
| Click into a web text field and type | **Passes**: the field holds "hello". Finding: the click also gives the web view focus, so iOS raises the phone's own keyboard over the trackpad (seen in the screenshot). Typing still works either way; whether that is wanted is Mike's call. |
| Two-finger scroll of a scrollable box | **Passes**: the list scrolled 800 points |
| Launcher: aim at a tile and click opens a web window | **Passes** (3 to 4 windows) |
| Arrange keeps windows apart and moves the launcher aside | **Passes** |
| Lock screens stops a move | **Passes** |
| Trackpad gestures, Spatial Mouse, a hardware mouse and keyboard, the window bar keys, Control Center | Written; **not driven** by the self-test. Need a person (Simulator or device). |
| On the glasses | **Untested**: needs a USB-C iPhone or iPad. |

Decisions made while building, for Mike to know:
- **One picture for both eyes.** A live web page can be drawn once only, so web windows have no per-window depth
  in 3D side by side. The glasses stay in 2D (1920x1080), which is what iOS gives anyway unless the Aura's
  control link works (phase 0's open question). PC screens (phase 2) are decoded frames and could get depth.
- **Curve is not drawn.** Core Animation cannot bend a live view; the window model keeps the curve value for
  later. Flat windows only for now.
- **Clicks reach web pages as DOM events** (pointer, mouse, click, focus), because iOS lets no app send touches to
  a view. Most sites respond; sites that check for trusted events (some players, fullscreen, pop-ups) may not.

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
By 22 Nov 2026 this repo had used 67 macOS minutes in November (670 of the 2,000; about $4.15 at list price,
charged $0). About 25 of those were one run stuck booting the Simulator before step timeouts were added. A full run
takes about 4 to 5 minutes, so roughly 29 more fit this month; the allowance resets on 1 December. With no payment method on the organisation, runs stop when the minutes are
used up; nothing is charged. Making the repo public makes them free.
