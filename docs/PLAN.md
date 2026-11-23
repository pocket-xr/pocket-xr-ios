# Pocket XR for iPhone and iPad — plan

Written 21 Nov 2026, revised the same day for Mike's ask that it "must completely match the
android version" (Pocket XR for Android 1.6.5). Nothing here has been built or tried on an iPhone
yet. Points marked **untested** are reasoned from Apple's documentation and other people's
reports, not seen.

## 1. What iOS allows, in short

- **Glasses as a screen: yes.** A USB-C iPhone (15 or later) or USB-C iPad sends DisplayPort to
  the glasses. An app can take that display for its own picture (a second `UIWindowScene` with the
  role `windowExternalDisplayNonInteractive`) while the phone shows the trackpad. It lasts only
  while Pocket XR is the app in front; switching apps or locking the phone hands the glasses back
  to plain mirroring.
- **Other apps' windows: no.** iOS has no way for one app to show, size or control another app's
  window. No Shizuku, no virtual displays, no accessibility service equivalent.
- **USB from an app: mostly no.** No USB HID on iPhone without MFi. On M-series iPads, Apple's
  USBDriverKit can talk to a USB device, but only with an entitlement Apple grants per device
  (**untested**, may be refused for someone else's glasses).
- **The glasses' USB network (Aura, One family): unknown.** iOS 16 and later have a CDC-NCM driver
  for USB Ethernet. If it brings up the glasses' link, an app can reach 169.254.2.1 (sensor on TCP
  52998, control link) after the Local Network prompt. Nobody has shown this on an iPhone yet.
  Phase 0 answers it, and much of the table below depends on the answer.
- **Building:** App Store uploads need Xcode 26 (since 28 April 2026), which needs macOS Sequoia;
  Mike's MacBook Air (2018/2019 model) cannot run Sequoia. Builds would run on GitHub Actions
  (section 4).

## 2. Android features, one by one

Key: **Same** = can match Android. **Close** = possible but different. **No** = Apple's rules
or hardware make it impossible; the closest match is given. "If NCM" = only if phase 0 finds the
glasses' USB network works on iOS.

### Windows in space

| Android feature | iOS | How, or the closest match |
|---|---|---|
| Any phone app opens as a window | **No** | iOS never lets an app host another app's window. Closest: (1) **web windows**, any website or web app (Gmail, YouTube, Docs, Netflix in the browser) in its own floating window, as many as the phone can run; (2) **PC screens** give real desktop apps; (3) on an iPad with an M chip, Apple's own Stage Manager on the glasses gives real iPad app windows, but flat and without Pocket XR or head tracking. |
| Move, resize, snap, curve, push and pull windows | **Same** | For Pocket XR's own windows (web, PC screens). |
| Adjust all, Arrange layouts, window presets, Share and Import layouts | **Same** | Layouts share through the iOS share sheet and Files. Presets reopen web pages and PC screens, not phone apps. |
| Lock screens | **Same** | |
| Window buttons: Back, Reopen, Switch app, Wide view, Close | **Close** | Back, Reopen and Close for web windows; Switch app becomes "switch source" (another site or PC screen). Wide view becomes the desktop version of a site. |
| Window shapes, Fit video, Immersive | **Same** | For own windows. |
| Text size for each app | **Close** | Page zoom for web windows; screen scale for PC screens. |
| Readability (1.6.4) | **Same** | Web windows lay out at 4/3 the density, PC screens at a smaller resolution, Readability screen size and angle as on the other versions. |
| Scroll by swiping | **Same** | For web windows. |
| Side by side 3D for a window, 2D while moving | **Same** | Pocket XR draws each window itself, so it can split a side by side video between the eyes. |
| Launcher with search, date, time | **Close** | Launches web bookmarks, PC screens, PC VR and Pocket XR's own pages. It cannot open phone apps in the glasses: opening one on the phone takes the glasses back to mirroring. |
| Launcher status: battery, cell signal, Wi-Fi | **Close** | Battery yes. Wi-Fi name needs location permission and a special entitlement; cell signal has no public API, so these two are left out or shown as connected/not connected. |
| Control Center: layouts, presets, recentre | **Same** | |
| Control Center: Wi-Fi, Bluetooth, quick settings toggles | **No** | Apps cannot switch these on iOS. Closest: show their state and a button that tells you to use iOS Control Center. |
| Notifications page (add-on) | **No** | iOS gives no app other apps' notifications. Closest: none; iOS banners show on the phone only. |
| Record the glasses (1080p video) | **Same** | Pocket XR draws every frame itself, so it can write them to a video and save it to Photos. PC screen pictures included. |
| Wide view for phone-shaped apps | **No** | No phone apps in windows; see above. |

### Seeing it

| Android feature | iOS | How, or the closest match |
|---|---|---|
| Head tracking, Aura and One family (1000 Hz over USB network) | **If NCM** | Same code as the Mac version. If the link does not come up: **No**, closest is the glasses' own anchor (One family, Beast) or two-finger panning on the phone. |
| Head tracking, Air family and VITURE (USB HID) | **No** on iPhone | HID is closed. Closest: VITURE Beast's own 3DoF hold; the Air family has none, so fixed screens. On M-series iPads, USBDriverKit could read HID if Apple grants the entitlement (**untested**, uncertain). |
| 3D side by side, switched by Pocket XR | **Close** | Drawing side by side: same. Switching the glasses to 3D: Aura only if NCM (command 10274); One and Beast are switched by the user in the glasses' menu, as on Android for the Beast. Whether iOS offers the 3840x1080 mode once the glasses switch is **untested**. |
| Steady mode, screen gap, remembered | **If NCM** | Needs the Aura and One control link (Ultrawide 10278, Spatial Anchor 10405). Without it: **No**, closest is the One's own Anchor mode with a wide canvas. |
| Steady mode in 6DoF (Aura, One with Eye) | **If NCM** | Same as Steady mode. |
| Smooth Follow, recentre, Head scroll, Cursor follows head | **Same** where there is tracking | |
| Window glow and colour, dark glass design | **Same** | |
| Each model's field of view, axes and calibration | **Same** | For the models iOS can read. |

### Controls

| Android feature | iOS | How, or the closest match |
|---|---|---|
| Trackpad: tap, two-finger scroll and pinch, three-finger swipes, scroll strip | **Same** | On the phone screen while the glasses show the Space. The Flip cover screen has no iPhone equivalent. |
| Spatial Mouse (point the phone) | **Same** | Phone gyroscope through Core Motion. |
| Bluetooth or USB mouse and keyboard | **Same** | Game Controller framework (GCMouse, GCKeyboard) inside Pocket XR. |
| Typing from the phone's keyboard, shortcut row (Esc, Tab, Ctrl, Alt, Win, arrows) | **Same** | |
| Hand tracking with the Aura's camera | **No** on iPhone, **Close** on iPad | iPhones cannot use USB cameras; iPads (iPadOS 17 and later) can, but Aura firmware 16.1.04 no longer offers its camera over USB. Closest: the phone's or iPad's own front camera with Apple's Vision hand pose, with the phone on a desk facing you (**untested**). |
| Hands held up for Adjust all | **Close** | Only with the camera fallback above. |
| Game controller: Gamepad mode (phone as a real controller for games) | **Close** | iOS apps cannot be a system controller for other apps. For PC screens and PC VR, Pocket XR sends a virtual controller to the PC, which Moonlight already supports. |
| Game controller: Touch mode, Game keys | **Close** | For PC screens only (there are no phone apps in windows). |
| Pocket mode (phone in the pocket) | **Close** | The proximity sensor can blank the screen; whether the glasses keep Pocket XR's picture while the screen is off is **untested**. |
| DeX cursor outside the Space (add-on accessibility service) | **No** | No accessibility services for apps on iOS, and no flat desktop outside Pocket XR. Closest: none. On iPad with a mouse, iPadOS's own pointer works on the glasses in Stage Manager. |

### PC

| Android feature | iOS | How, or the closest match |
|---|---|---|
| PC screens, up to three, from Windows, Mac and Steam Deck | **Same** | moonlight-common-c (C, works on iOS; Moonlight's own iOS app uses it) with VideoToolbox decoding. Same pairing with Pocket XR for Windows, Mac and Deck. Licence question in section 5. |
| Each PC screen's sound, mouse and keyboard settings | **Same** | |
| PC VR (SteamVR through ALVR's streamer and the PC helper) | **Close** | Needs an ALVR client on iOS. ALVR's client core is Rust and has been built for Apple devices (an open source ALVR client for Vision Pro exists), so it is possible but is the largest single piece. Head pose from the glasses if NCM; otherwise PC VR has no head tracking and is not worth shipping. |
| Joy-Cons as controllers | **Same** | iOS pairs Joy-Cons through Bluetooth and the Game Controller framework reads them. |
| Hands as PC VR controllers | **No** on iPhone | Needs the glasses' camera; see hand tracking. |
| OpenXR runtime for other apps | **No** | iOS apps cannot load another app's runtime. Closest: none. |

### The app

| Android feature | iOS | How, or the closest match |
|---|---|---|
| Tour, practice pad, setup checklist | **Same** | Checklist shows glasses, Local Network and PC pairing instead of Shizuku. |
| Glasses setup check | **Same** | Steps differ by model (no HID tracking on Air glasses). |
| 11 languages | **Same** | Android's string files can be converted. |
| Settings for windows, hands, trackpad, with resets | **Same** | |
| Save and restore settings to a file | **Same** | Through Files. Could even read an Android settings file. |
| Glasses report, Send logs to Mike | **Close** | iOS shows far less about USB devices (no ids or descriptors), so reports say less. |
| Update check against GitHub, Obtainium | **No** | Not allowed on the App Store; the App Store updates the app, as Play does on Android. |
| Ko-fi row | **No** in the App Store build | Left out, as on the Play build. |
| Shizuku, the add-on, 16 KB pages, Play Protect notes | n/a | Android-only. |

### What this means

- Matches well: the Space's window handling for Pocket XR's own windows, the trackpad and
  Spatial Mouse, mouse and keyboard, PC screens, Readability, recording, layouts, the tour,
  languages and settings.
- Depends on phase 0 (the USB network): head tracking, 3D switching on the Aura, Steady mode,
  and with them PC VR.
- Cannot match, because of Apple's rules: phone apps as windows, the notifications page, the DeX
  cursor, Wi-Fi and Bluetooth toggles, Gamepad mode for other apps, the OpenXR runtime, the GitHub
  update check, and hand tracking with the glasses' camera on iPhone. Air family and VITURE head
  tracking cannot match on iPhone (maybe on M-series iPads).

Mike decides what to do about each gap.

## 3. iPhone and iPad

- iPhone 15 or later (USB-C). iPhone 15 and 15 Plus have USB 2 data but still send video.
- USB-C iPads work the same way and have more room to run several web windows and PC screens.
  Only iPads can use USB cameras (iPadOS 17+) and, on M chips, USBDriverKit. Both are **untested**
  for the glasses.

## 4. How to build and sign

### The Air cannot make App Store builds
- App Store Connect only accepts apps built with Xcode 26 and the iOS 26 SDK (since 28 April 2026).
- Xcode 26 needs macOS Sequoia (15) or later. Mike's MacBook Air (i5-8210Y, 2018/2019 model,
  macOS 14.8.8) cannot install Sequoia: Apple dropped the 2018 and 2019 MacBook Air.
- So the Air can at most run Xcode 16.x for local compile checks. It cannot upload to TestFlight
  or the App Store.

### Proposed: build in the cloud on GitHub Actions
- GitHub's macOS runners have Xcode 26 and are free for public repos.
- Signing without a Mac of ours: an App Store Connect API key (role App Manager or Admin) lets
  `xcodebuild -allowProvisioningUpdates` make the distribution certificate and profile itself
  (Apple's cloud-managed signing), then upload the build to TestFlight.
- The loop runs from this PC: push, CI builds, the build appears in TestFlight, Mike installs it on
  his iPhone from the TestFlight app. The Air stays free for the Mac sessions.
- Alternative: Xcode Cloud (25 free hours a month with the membership); setting it up normally
  needs Xcode on a Mac first, so GitHub Actions is simpler here.

### What only Mike can do
- Say which iPhone or iPad he has (USB-C needed) and its iOS version.
- In App Store Connect: create the app record (name "Pocket XR", bundle id
  `com.hayeco.pocketxr.ios` proposed) and an API key with App Manager role. The existing notary
  key may already have the right role (Users and Access, Integrations).
- Put the key (.p8, key id, issuer id) into the GitHub repo's Actions secrets himself.
- TestFlight testers, export compliance, age rating, privacy answers, screenshots, and pressing
  Submit for review.

## 5. How to release, and review risks

1. **TestFlight internal** (Mike and up to 100 team members): no Apple review, builds ready minutes
   after upload. This is the test loop.
2. **TestFlight external** (public link for Reddit testers): light Beta App Review, about a day.
3. **App Store**: full review, often one to three days.

Risks:
- **Reviewer has no glasses (4.2, 2.1).** The app must work on any external display (AirPlay to a
  TV, a USB-C monitor); a video with glasses goes in the review notes.
- **Web windows (4.2.2).** Apps that are "just a browser" are sometimes rejected; here they are one
  part of a spatial workspace, which should be fine, but it is a judgement call by the reviewer.
- **Remote desktop (4.2.7).** Allowed if it connects only to the user's own computer. PC screens
  and PC VR fit this.
- **GPL and the App Store.** Pocket XR and moonlight-common-c are GPL-3.0. Some argue App Store
  terms conflict with GPLv3; only copyright holders can act on it (VLC was pulled in 2011 after a
  contributor objected). Safest is to ask the Moonlight developers for their OK before TestFlight
  external or the App Store.
- **Names (5.2).** "XREAL", "VITURE" in the description as "works with" only, not in the name or
  icon.
- **Local Network prompt** needs a clear reason (the PC, and the glasses' link).
- **Encryption export question:** standard AES and TLS only, declared exempt in Info.plist.
- Privacy policy URL; the app collects nothing, so the privacy label is "no data".

## 6. Phases and rough size

Full parity is much bigger than the first plan. Sizes are in Claude sessions like those that made
the Mac version; each phase ends with Mike trying a TestFlight build.

| Phase | What | Rough size | Needs Mike |
|---|---|---|---|
| 0 | Repo, Xcode project, GitHub Actions to TestFlight; **probe app**: test picture on the glasses, available display modes, whether the USB network and 52998 come up | 1 | App record, API key secrets, install from TestFlight, plug in the Aura (and a One if a tester has one) |
| 1 | The Space: canvas on the glasses, windows (move, resize, snap, curve, push, pull, lock, shapes), web windows, launcher, Control Center, trackpad, Spatial Mouse, mouse and keyboard, head tracking and 3D if NCM | 3-4 | Try in glasses |
| 2 | PC screens (moonlight-common-c, pairing, VideoToolbox, three screens, sound, game controller and game keys to the PC), Readability | 2-3 | Try with his PC |
| 3 | Steady mode (if NCM), recording, layouts and presets, sharing, settings save/restore, tour, setup check, 11 languages | 2-3 | Try, review text |
| 4 | PC VR (ALVR client on iOS, Joy-Cons) | 3-4 | Try with SteamVR |
| 5 | Camera hand tracking fallback (**untested** idea), App Store text and screenshots, external TestFlight, submission | 1-2 | Moonlight OK, submit |

About 12 to 17 sessions in all. Phase 0 can change this a lot: if the USB network does not come
up, head tracking, Steady mode and PC VR drop out or shrink, and the rest gets smaller too.

## 7. Questions for Mike

1. Which iPhone/iPad do you have with USB-C, and which iOS?
2. Is building and signing on GitHub Actions (key stored as a repo secret) fine?
3. Public repo `pocket-xr/pocket-xr-ios` from the start, like the Windows and Mac ones?
4. OK to start phase 0? The gaps marked **No** can be decided after it, once we know what the USB
   network allows.
