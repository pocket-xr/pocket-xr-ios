# Public TestFlight for community testers

Drafted 23 November 2026 for Mike to check. Nothing here has been entered in App Store Connect, submitted to Apple or
posted anywhere. Every drafted public text below has no colons outside web addresses and says what is untested.

The build is Pocket XR 0.1.0 build 2, uploaded 22 November 2026. It is the same app as the Simulator tests; nobody has
run it on a real iPhone or iPad yet.

## What Mike does in App Store Connect (in this order)

All at https://appstoreconnect.apple.com/apps, then Pocket XR, then the **TestFlight** tab.

1. **Check the build arrived.** Under iOS builds, 0.1.0 (2) should be listed with no warning sign. If it asks about
   encryption, it should not (the app answers it), but if it does, answer that it uses only standard encryption (exempt).
2. **Test Information** (left side, under General Information). Fill in:
   - Beta App Description: the text in "Beta app description" below.
   - Feedback Email: connect@mikehaye.com (or another address Mike prefers).
   - Marketing URL: optional; the Pocket XR site.
   - **Privacy Policy URL: required for public testing.** This repo is private, so `PRIVACY.md` must be put somewhere
     public first: the Pocket XR site, or the public pocket-xr repo. Mike's call; tell me and I prepare it.
   - Beta App Review Information: Mike's name, phone and email; **Sign-in required: off**; Review Notes from
     "Notes for Apple's beta review" below.
3. **Create the external group.** Left side, "+" next to External Testing, group name `Community testers`.
4. **Add the build to the group.** In the group, Builds, "+", choose 0.1.0 (2). Paste "What to test" below.
5. **Submit for Beta App Review.** The first build of an external group goes to Apple's beta review. Usually about a
   day. **This is the step that needs Mike's yes.**
6. **Public link.** Once approved, in the group, turn on Public Link, set a tester limit (for example 100), and copy the
   link. It goes into the Reddit post.

## Beta app description (testers see this in the TestFlight app)

Pocket XR turns an iPhone or iPad and a pair of XR glasses into a spatial workspace. Web pages and your computer's
screens float around you as windows. The phone is the trackpad and keyboard. Free and open source, with no ads and no
accounts.

This is the first test of the iPhone and iPad version. It has only run on Apple's iPhone simulator so far, never on a
real iPhone, iPad or glasses. Expect things to break. Your report tells us what iOS allows with your glasses.

You need an iPhone 15 or later, or an iPad with USB-C, and XR glasses that plug into USB-C as a screen, such as XREAL
or VITURE glasses.

## What to test (this build)

Plug your glasses into the USB-C port with Pocket XR open.

1. Look in the glasses. Do you see Pocket XR's windows, or only a copy of the phone's screen?
2. Turn your head. Do the windows stay where they are, or move with you?
3. Open the gear icon, then Glasses and head tracking details, then Share report. Send it to us.

Also worth a try if you have time. A web page from Apps. Steady mode and Readability in the Control Center. A PC screen
if you run Pocket XR on a Windows PC, Mac or Steam Deck.

Untested so far. Everything on a real device. Head tracking from the glasses. The glasses switching to 3D. Steady mode
in the glasses. PC screens over Wi-Fi. PC VR.

## Notes for Apple's beta review (Review Notes)

Pocket XR is a workspace for XR glasses that connect to an iPhone or iPad as an external display. Without glasses, the
whole workspace shows in a live preview at the top of the phone screen, so it can be tried with no extra hardware.

1. Open the app and skip or finish the tour.
2. Tap Apps. The launcher opens in the preview. Move one finger on the trackpad to move the pointer and tap to click.
3. Open a site from the launcher. Scroll with two fingers. Tap Keyboard to type.
4. Tap Control for the Control Center. Arrange windows, lock them, try Steady mode and Readability.

PC screen streams the user's own computer, which the user pairs with a PIN. PC VR streams the user's own PC through
ALVR. The app has no accounts, no server and no content of its own.

This beta asks community testers with glasses to tell us how their glasses behave on iOS.

## Short tester instructions (for the Reddit post, a GitHub discussion or a reply)

What you need. An iPhone 15 or later, or a USB-C iPad. XR glasses that work as a USB-C screen.

1. Install TestFlight from the App Store, then open the test link.
2. Open Pocket XR, then plug in your glasses.
3. Note what the glasses show, and what happens when you turn your head.
4. In Pocket XR tap the gear icon, then Glasses and head tracking details, then Share report. Send it to us by email or
   paste it in the thread.

The report says which glasses display mode iOS gave the app, whether the glasses' head tracking came through, and the
app's own log. It also lists your phone's local network addresses, such as 192.168.1.20. It contains nothing else about
you.

## Reddit post (draft)

**Title**

Pocket XR for iPhone and iPad, looking for testers with XR glasses

**Body**

Pocket XR is the free spatial workspace for XR glasses that runs on Android, Windows, Mac and Steam Deck. There is now
an iPhone and iPad version, and it needs testers.

Windows float around you, web pages and your computer's screens. The phone is the trackpad and keyboard. Readability,
Steady mode and up to three PC screens are in.

It has never run on a real iPhone. I don't own one, so everything so far was tested on Apple's simulator. The big
questions are what iOS allows with glasses. Does Pocket XR get its own picture in the glasses? Does head tracking from
the glasses come through? Your report answers that in five minutes.

You need an iPhone 15 or later or a USB-C iPad, and XR glasses that plug in as a screen. XREAL Aura and One owners are
the most useful right now, since head tracking may work for them. Air and VITURE owners help too, as iOS doesn't let apps
read their motion sensors, but the windows should still show.

Join the test here https://testflight.apple.com/join/XXXXXXXX

Open Pocket XR, plug in your glasses, and turn your head. Then tap the gear icon, Glasses and head tracking details,
Share report. Post it here or send it to connect@mikehaye.com.

Untested so far. Everything on a real device. Head tracking. 3D. Steady mode in the glasses. PC screens over Wi-Fi.
PC VR. Expect rough edges.

Pocket XR is a community project, not made by XREAL or VITURE. Free, open source, no ads, no accounts.

## Before Mike says yes

- The privacy policy needs a public address (step 2).
- The GPL question (Moonlight's code) matters for the App Store. For TestFlight it is the same code in Apple's hands, so
  Mike may want the note to Moonlight's developers sent first (draft in APPSTORE-LISTING.md).
- The source is still private. TestFlight testers get the app without the source; the GPL asks that the source is
  offered to them. Making the repo public before the public link goes out is the simple way.
- The test link goes into the Reddit post once Apple approves the build.
