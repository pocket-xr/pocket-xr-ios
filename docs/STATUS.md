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

## Phase 1: the Space (22 Nov 2026)

Checked in CI on the iOS 26.4.1 Simulator with no glasses, last in run 44974545976: the Space draws on the phone as
a preview, the fake glasses turn the head, and a self-test (App/SpaceSelfTest.swift) drives the Space the way the
trackpad does and reads every result back from the pages and the Space itself. Screenshot: phase1-simulator.png
(the self-test leaves side by side on, so it shows both eyes).

| Item | State |
|---|---|
| Window model: open beside others, move, resize, push and pull, snap, arrange, make room, Adjust all, Lock screens, shapes, focus order, save and load | **Passes** the core checks (Checks/WindowChecks.swift; over 1,100 checks in all) |
| Windows drawn in 3D from the head pose (Core Animation, live views) | **Seen** in the Simulator preview, following the fake glasses' head turn |
| Head tracking through HeadPose (prediction, draw smoothing, Still lock, Smooth Follow), as on the Mac and Deck | Built; runs against the fake glasses in CI. **Untested** on real glasses. |
| Click on a web page through the pointer | **Passes**: the page's button reports "clicked 1" |
| Click into a web text field, type, Backspace | **Passes**: "hellp", Backspace, "o" leaves "hello" |
| The phone's keyboard comes up only with the Keyboard button (Mike's choice, 22 Nov 2026) | **Passes**: after the click into the field no keyboard is up |
| Two-finger scroll of a scrollable box | **Passes**: the list scrolled 800 points |
| Launcher: a tile opens a web window | **Passes** |
| Arrange keeps web windows apart and moves the launcher aside | **Passes** |
| Lock screens stops a move | **Passes** |
| Control Center: Lock screens switch, a shape (9:16) for the last web window | **Passes**: locked, and the window's content became 9:16 with its view resized to match |
| Window keys on a window's bar: Close | **Passes** |
| Side by side when the display is 3840x1080 (glasses in 3D): the one eye's picture in both halves | **Passes** in the Simulator (forced on): both halves show the same live windows |
| Trackpad gestures, Spatial Mouse, a hardware mouse and keyboard, the other window keys, Smooth Follow, saved layouts in the Control Center | Written; **not driven** by the self-test. Need a person (Simulator or device). |
| On the glasses | **Untested**: needs a USB-C iPhone or iPad. |

Limits found while building, for Mike to decide on:
- **No per-window depth for web windows in 3D.** A live web page can be drawn from one eye position only, so in
  side by side both eyes get the same picture: every window sits at the glasses' own focus distance. PC screens
  (phase 2) are decoded frames and could get depth.
- **Curve is not drawn.** Core Animation cannot bend a live view, and iOS has no public way to show a live view
  more than once in pieces. The model keeps each window's curve for later; windows are flat. The closest match
  would be drawing a curved window from snapshots of the page, a few times a second instead of live.
- **Clicks reach web pages as DOM events** (pointer, mouse, click, focus), because iOS lets no app send touches to
  a view. Most sites respond; sites that check for trusted events (some players, fullscreen, pop-ups) may not.
- **Not done in phase 1:** switching the Aura into 3D and Steady mode (need the glasses' USB network, phase 0's
  open question; planned for phase 3), hand tracking (no camera path on iPhone), Readability (phase 2, with PC
  screens).

## Phase 2: PC screens and Readability (22 Nov 2026)

How it is built: Moonlight's stream core (moonlight-common-c 874ac95, the copy Pocket XR for Android and Windows use,
GPLv3) is built three times with prefixed names (scripts/gen-moonlight.sh), so up to three PC screens can stream in
one iOS process, where Android and Windows use one process per screen. Its crypto runs on CommonCrypto and CryptoKit
(no OpenSSL). Pairing, the client identity (kept in the keychain), the Pocket XR helper words, video into an
AVSampleBufferDisplayLayer (hardware decoding) and Opus sound (AVAudioConverter) are ported from Pocket XR for Windows.

Checked in CI runs 44976618853 and 44978208181 against a stand-in computer (screenshot: phase2-simulator.png, the stand-in's screen in a PC screen, both eye halves): Pocket XR for Mac's computer side, built from its public
repo on the runner and run with its test mode (PXR_HOST_TEST=1, it captured the runner's own screen), on
127.0.0.1:50989, with the PIN given by its `--host-pin`.

| Item | State |
|---|---|
| Moonlight's core built three times for iPhone, iPad and the Simulator | **Passes** |
| Client identity: RSA key and certificate in the keychain, TLS client certificate | **Passes** in the Simulator (ad hoc signed for the keychain) |
| Pairing with a Pocket XR host (PIN), HTTPS with the pinned certificate, app list, launch | **Passes**: "paired", launch at 1920x1080@60 |
| RTSP, control, video and sound streams | **Passes**: H.264 1920x1080, 95 of 95 frames into the video layer, layer not failed |
| Sound (Opus, 48 kHz stereo, 5 ms packets) | **Passes**: 3,396 of 3,396 packets decoded and queued to the speaker (first try with AudioConverter decoded none; AVAudioConverter does) |
| A click in the PC screen reaches the computer | **Seen** in the host's log ("3 input events") |
| PC screen in the Space as a window; launcher tile; Close ends the host's session | Built; window and tile used by the self-test |
| Pocket XR helper words (find, allow, PIN, status, screen-prepare) | Built; the stand-in host answered "say Yes" (allow) during pairing; not checked further |
| Readability: web pages at 4/3 zoom, PC screens at 3/4 of the pixels each way, in the Control Center | **Passes**: web zoom 1.33; PC screens started again at 1440x808 and streamed (808, not 810: sizes are kept to multiples of 8, as on Windows) |
| Two PC screens at once (copies 1 and 2 of the core) | **Passes** (run 44978208181): the stand-in's first and second instances, 118 and 93 frames shown, sound from PC screen 1 only (2,872 of 2,872 packets). Three at once: built, not tried. |
| Finding computers by mDNS (_nvstream._tcp) as well as the helper; typing an address with the Keyboard key when none is found; the PIN page named for Apollo and Sunshine | Built; **not driven** by the self-test (CI gives the address). On the runner the stand-in could not announce itself by mDNS (error -72004), so mDNS is untested. |
| Real PC over Wi-Fi, latency, a sleeping PC, reconnects, keyboard keys into the PC, a phone keyboard and mouse into the PC | **Untested** |
| HEVC | Offered when the device decodes it in hardware; the Simulator's run used H.264 |

## Phase 3: Steady mode, Record, files, tour, languages (22 Nov 2026)

Checked in CI runs 44979305340 and 44980123316 on the Simulator.

| Item | State |
|---|---|
| Steady mode: windows in a row, one picture across the display (never side by side), head held still; remembered | **Passes** in the Simulator (drawing only) |
| Steady mode in the glasses: Ultrawide and Spatial Anchor through PocketXRCore's SettingsControl (the Deck's and Mac's code), started when the glasses' USB link is up | Built; **untested**: needs the USB link on a real device (phase 0's open question). With no link, Steady mode is drawing only, for glasses that hold the picture themselves. |
| Record: the glasses' view to an H.264 video, saved to Photos | **Passes**: 3 s recorded, 63 to 77 frames, 3.2 s long; a frame taken from the video shows the PC screen in it. Photos itself not tried (the test keeps the file). |
| Save settings to a file and restore it; Share layouts and Import layouts | **Passes**: 3 windows before and after a restore, layouts imported |
| Tour (nine pages, first start and from Settings), glasses setup check (steps for each model; iOS cannot tell the model, so the user picks it) | Built; **not driven** by the self-test |
| 11 languages, as on Android: English, Korean, Japanese, Chinese (simplified and traditional), Spanish, Portuguese (Brazil), French, German, Italian, Russian | **In the app**: all 11 compiled (CI checks German and Japanese). The translations are new and unchecked by a native reader. The glasses and head tracking details screen and some error lines stay in English. |

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
By 22 Nov 2026 this repo had used about 115 macOS minutes in November (about 1,150 of the 2,000; charged $0). A full run takes about 5 minutes, so roughly 17 more fit this month; the allowance resets on 1 December. With no payment method on the organisation, runs stop when the minutes are
used up; nothing is charged. Making the repo public makes them free.
