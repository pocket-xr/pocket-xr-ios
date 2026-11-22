# App Store listing, review notes and release checklist

Drafted 22 November 2026 for Mike to check before anything is submitted. Nothing here has been entered anywhere.

## The listing (English; App Store Connect, the app's page, version 1.0)

- **Name:** Pocket XR
- **Subtitle (30 characters):** Spatial desktop for XR glasses
- **Category:** Productivity (secondary: Utilities)
- **Price:** Free. No in-app purchases.
- **Age rating:** the questionnaire's "Unrestricted web access" has to be **Yes** (the app opens any web page), which
  makes it 17+. There is no way round that with a browser inside.
- **Support URL:** https://github.com/pocket-xr/pocket-xr/discussions
- **Marketing URL:** the Pocket XR site
- **Privacy policy URL:** needs a public page. This repo is private, so `PRIVACY.md` here must be published first, for
  example on the Pocket XR site or in the public pocket-xr repo. Mike's call where.
- **Copyright:** 2026 Haye & Co

**Promotional text (170):**
Your XR glasses become a workspace: web pages and your computer's screens float around you, held still as you turn
your head. Free, open source, no ads, no accounts.

**Description:**

Pocket XR turns your iPhone or iPad and a pair of XR glasses into a spatial workspace.

Plug your glasses into the USB-C port and the Space opens on them: windows float around you at their own size and
distance. Move them, resize them, push them back or pull them closer, snap them side by side, arrange them in one tap,
and lock them in place.

YOUR COMPUTER IN YOUR GLASSES
With Pocket XR on your Windows PC, Mac or Steam Deck, or with Apollo or Sunshine, open your computer's desktop as a
window in the Space, with sound. Up to three screens at once. The phone is the trackpad and keyboard.

THE WEB, AROUND YOU
Open any site in its own window: mail, documents, video, search.

YOUR PHONE IS THE CONTROLLER
A trackpad with taps, two-finger scrolling, pinch and three-finger swipes. Point the phone like a laser with the
Spatial Mouse. Bluetooth mice, keyboards and game controllers work too.

MADE FOR READING AND WORKING
Readability makes text a third bigger on 1080p glasses. Steady mode lines your windows up in front of you and lets the
glasses hold the picture still. Record what your glasses show.

PC VR (EXPERIMENTAL)
Play SteamVR games from your Windows PC through the free Pocket XR PC helper, with a game controller or Joy-Cons.

Works with XR glasses that connect to a USB-C iPhone or iPad as a screen, such as XREAL and VITURE glasses. Head
tracking depends on the glasses and what iOS allows; the glasses setup check in the app shows what yours can do.

Pocket XR is a community project, not made by or affiliated with XREAL or VITURE. Free and open source (GPL-3.0).

**Keywords (100 characters):**
xr,ar glasses,xreal,viture,spatial,virtual desktop,monitor,remote desktop,moonlight,workspace,vr

(Brand names in keywords: Apple allows names of products the app works with; review may still query them.)

## Review notes (App Review Information, Notes)

Pocket XR is a spatial workspace for XR glasses that connect to an iPhone or iPad as an external display. Without
glasses, everything shows in a live preview at the top of the phone screen, so the app can be tried without any
hardware:

1. Open the app and skip or finish the tour.
2. Tap Apps: the launcher opens in the preview. Tap the trackpad to click; move one finger to move the pointer.
3. Open a site from the launcher; scroll with two fingers; tap Keyboard to type.
4. Tap Control for the Control Center: arrange windows, Lock screens, Steady mode, Readability, Record.
5. With a USB-C monitor connected, the Space moves to it, as it does to glasses.

PC screens stream the user's own computer only (GameStream protocol, as Moonlight; guideline 4.2.7): the user pairs
their own computer with a PIN. PC VR streams SteamVR from the user's own PC through ALVR. No account, no server, no
content is offered by the app itself.

A video of the app with XREAL Aura glasses: (Mike to add a link; recorded with Record or a phone pointed at the
glasses).

## Before submitting: checks for Mike

- **The GPL question.** Pocket XR (GPL-3.0) includes moonlight-common-c (GPL-3.0). Some argue the App Store's terms
  conflict with GPLv3, and only the copyright holders can act on it (VLC was pulled in 2011 after one contributor
  objected). Moonlight's own iOS app is on the App Store. Suggested: ask the Moonlight developers first. A draft, with
  no colons, as Mike's GitHub posts have none:

  > Hello Moonlight team. I make Pocket XR, a free GPL-3.0 spatial workspace for XR glasses, on Android, Windows, Mac
  > and Steam Deck. Its PC screens use moonlight-common-c unchanged, credited in the app and the source. I would like to
  > publish the iPhone and iPad version on the App Store, free, with its full source public, as Moonlight for iOS is.
  > Would you be happy with that? If you would rather it did not ship there with your code, I will respect that.
  > Thank you for Moonlight. Mike

  Where to send it is Mike's choice (a GitHub discussion on moonlight-stream, or their Discord). Not sent.
- **ALVR** is MIT: no question.
- **The privacy policy page** made public (above).
- **The repo made public** before or at release, so the GPL's source offer is met (Mike's plan: private until it works).
- **App Privacy** in App Store Connect: "Data Not Collected".
- **Export compliance:** answered in the app (ITSAppUsesNonExemptEncryption false: only standard encryption, for the
  user's own streams).
- **Screenshots:** made in CI (the Screenshots workflow): iPhone 6.9" and iPad 13". Real photos through the glasses would
  sell it better; Mike's call.
- **First release is TestFlight** (internal, no review), then external TestFlight (a light review), then the App Store.
