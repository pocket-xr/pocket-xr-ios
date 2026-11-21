# Pocket XR for iPhone and iPad — plan

Written 21 Nov 2026. Nothing here has been built or tried on an iPhone yet. Points marked
**untested** are reasoned from Apple's documentation and other people's reports, not seen.

## 1. What iOS allows

### Glasses as a screen — yes
- A USB-C iPhone (15 or later) or USB-C iPad puts out DisplayPort over the cable, so the glasses
  show up as an external display. By default iOS mirrors the phone.
- An app can take the external display for its own picture: a second `UIWindowScene` with the role
  `windowExternalDisplayNonInteractive`. The glasses then show Pocket XR's own view while the
  phone screen shows something else (our trackpad and controls). This is the normal, App Store
  approved way (video apps and presentation apps do it).
- Limits: it only lasts while Pocket XR is in front on the phone. Switching to another app or
  locking the phone hands the glasses back to mirroring. We keep the phone awake with
  `isIdleTimerDisabled` while the glasses are attached.
- Resolution: the Aura in 2D gives 1920x1080 on the Mac; iOS should get the same (**untested**).
  The 3840x1080 side-by-side mode needs the Aura control command 10274, which needs the USB
  network below.

### Glasses' motion sensor — unknown, must be tried first
- **Air family (HID):** closed. iOS has no USB HID access for apps without MFi. No head tracking
  from Air, Air 2, Air 2 Pro or VITURE HID glasses on iOS.
- **Aura and One (USB network, 169.254.2.1, TCP 52998):** iOS 16 and later have a CDC-NCM driver
  for USB Ethernet. If iOS brings up the glasses' NCM link as a wired network, an app can connect
  to 169.254.2.1 with `Network.framework`, pinned to that interface, after the user allows Local
  Network access. Nobody I could find has shown this working on an iPhone; one public project
  tried XREAL One sensor data on iPhone and calls it unconfirmed. This is the single biggest
  unknown, so the first build is a small probe app that answers it (section 5, phase 0).
- If the link comes up, the Aura control link works too: 3D mode (10274), Steady mode with
  Ultrawide (10278) and Spatial Anchor (10405), the same as on Mac.

### Fallbacks if there is no sensor link
- **The glasses' own anchor.** The XREAL One and VITURE Beast can hold the picture still by
  themselves. Pocket XR just draws a flat canvas and the glasses do the rest. This works with no
  data from the glasses at all.
- **Phone trackpad "look around".** Drag with two fingers on the phone to pan the screens.
- **Phone front camera (phase 2, untested).** With the phone on a desk, ARKit face tracking or
  Vision can follow the head. Not tried with glasses on the face; may not track well.
- The phone's own motion sensor does not help: the phone is in the hand, not on the head.

## 2. What the first version should be

iOS cannot host other apps' windows, so no floating iPhone apps. What does fit:

1. **PC screens** — the core. Stream one to three screens from a computer running Sunshine or
   Apollo, as the Android, Windows and Mac versions do. Use moonlight-common-c (the same C
   streaming core Moonlight uses) with Apple's VideoToolbox for H.264/HEVC decoding.
2. **Phone as trackpad and keyboard** for the PC: tap to click, two fingers to scroll, the iOS
   keyboard for typing.
3. **Floating screens on the glasses**, arranged as on the other versions, held still by head
   tracking where we have it (Aura, maybe One), otherwise by the glasses' own anchor.
4. **Readability**: one 1440x810 screen at about 30-34 degrees, for larger text.
5. **Built-in web screen** (optional): a browser view drawn on the glasses, so the app is useful
   without a PC.

Later, if wanted: the phone's own screen as a floating window via a ReplayKit broadcast extension
(the user starts it from Control Center; Apple allows it; memory limits are tight; **untested**).

## 3. How to build and sign

### The Air cannot make App Store builds
- Since 28 April 2026 App Store Connect only accepts apps built with **Xcode 26** and the iOS 26
  SDK.
- Xcode 26 needs macOS Sequoia (15) or later. Mike's MacBook Air (i5-8210Y, 2018/2019 model,
  macOS 14.8.8) cannot install Sequoia: Apple dropped the 2018 and 2019 MacBook Air.
- So the Air can at most run Xcode 16.x for local compile checks. It cannot upload to TestFlight
  or the App Store.

### Proposed: build in the cloud on GitHub Actions
- GitHub's macOS runners have Xcode 26 and are free for public repos.
- Signing without a Mac of ours: an App Store Connect API key (role App Manager or Admin) lets
  `xcodebuild -allowProvisioningUpdates` make the distribution certificate and profile itself
  (Apple's cloud-managed signing), then upload the build to TestFlight.
- The whole loop then runs from this PC: push, CI builds, build appears in TestFlight, Mike
  installs it on his iPhone from the TestFlight app. No Mac, no cable, and the Air stays free for
  the Mac sessions.
- Alternative: Xcode Cloud (25 free hours a month with the developer membership). Setting it up
  normally needs Xcode on a Mac first, so GitHub Actions is simpler here.

### What only Mike can do
- Confirm which iPhone or iPad he has (USB-C needed) and its iOS version.
- In App Store Connect: create the app record (name "Pocket XR", bundle id
  `com.hayeco.pocketxr.ios` proposed), and make an API key with App Manager role. The existing
  notary key N744CT6GJ2 may already have the right role; Mike can check under Users and Access,
  Integrations.
- Put the key (.p8, key id, issuer id) into the GitHub repo's Actions secrets himself.
- Add himself (and later testers) to TestFlight, answer export compliance, age rating and the
  privacy questions, provide screenshots approval, and press Submit for review.

## 4. How to release

1. **TestFlight internal** (Mike, up to 100 team members): no Apple review, builds are ready
   minutes after upload. This is our test loop.
2. **TestFlight external** (public link for Reddit testers): needs a light Beta App Review for
   the first build, usually a day.
3. **App Store**: full review, often one to three days.

### Review risks
- **Reviewer has no glasses (4.2 minimum functionality / 2.1 completeness).** The app must do
  something useful with any external display (AirPlay to a TV, a USB-C monitor) and we attach a
  short video of it working with glasses in the review notes.
- **Remote desktop rules (4.2.7).** Allowed if it only connects to the user's own computer and
  the app does not act as a store for the PC's content. PC screens fit this.
- **GPL and the App Store.** Pocket XR is GPL-3.0 and moonlight-common-c is GPL-3.0. Some argue
  the App Store terms conflict with GPLv3; only copyright holders can act on it (VLC was pulled
  in 2011 after a contributor objected). Moonlight's own iOS app is on the App Store, but that is
  its authors' choice for their own code. Safest is to ask the Moonlight developers for their OK
  before the App Store step. TestFlight carries the same question.
- **Names (5.2).** "XREAL", "VITURE" and so on may appear in the description as "works with",
  not in the app name or icon.
- **Local Network prompt** must have a clear reason string (finding the PC, and the glasses'
  link).
- **Encryption export question**: streaming uses standard AES and TLS, which counts as exempt; we
  answer it in Info.plist so each build does not ask.
- Privacy policy URL needed; the app collects nothing, so the privacy label is "no data".

## 5. Phases and rough size

| Phase | What | Rough size | Needs Mike |
|---|---|---|---|
| 0 | Repo, Xcode project, GitHub Actions to TestFlight; **probe app** that shows a test picture on the glasses and reports whether the USB network and 52998 come up | 1 session | App record, API key secrets, install from TestFlight, plug in the Aura |
| 1 | External display canvas, floating screens, Readability, phone trackpad, head tracking if phase 0 found the link | 1-2 sessions | Try in glasses |
| 2 | PC screens: moonlight-common-c, pairing with Sunshine/Apollo, VideoToolbox decoding, up to three screens | 2-3 sessions | Try with his PC |
| 3 | Steady mode (Aura), polish, tour, App Store text and screenshots, external TestFlight | 1-2 sessions | Review text, submit |

Phase 0 decides a lot: with the sensor link, iOS gets close to the Mac version; without it, iOS
is a "flat screens, glasses hold them still" version for the One and Beast, and plain fixed
screens on the Aura.

## 6. Questions for Mike

1. Which iPhone/iPad do you have with USB-C, and which iOS?
2. Is building and signing on GitHub Actions (key stored as a repo secret) fine?
3. Public repo `pocket-xr/pocket-xr-ios` from the start, like the Windows and Mac ones?
4. OK to start phase 0?
