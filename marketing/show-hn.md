# Show HN

**Title** (max 80 chars):

Show HN: Sidle – free, open-source trackpad edge gestures for Mac

**URL:** https://github.com/rp6186030/sidle

**First comment** (post immediately):

Hi HN. I kept reaching for the keyboard to change volume while my hand was already on the trackpad, so I built Sidle. Rest a finger on the right edge, click and slide: volume. Left edge: brightness. Bottom edge: scrub the video. Top corners take one to four clicks and can launch an app, press a hotkey or run a Shortcut.

How it works, since that is the interesting part:

- macOS does not give apps global finger positions, so Sidle dlopens the private MultitouchSupport framework and reads raw contact frames. That is also why it can never be on the App Store.
- A gesture only starts when exactly one finger is inside the edge strip at the moment of a physical click. A CGEventTap swallows that click so the app underneath never sees it. This is what keeps palms and scrolling from triggering anything.
- Distances are measured in millimetres from the sensor size, so a slide feels the same on a MacBook and a Magic Trackpad.
- Volume and brightness are sent as the same system key events the keyboard produces, so you get the normal macOS HUD and ⇧⌥ quarter steps for free.

Things I know are rough: it is not notarized (I am not paying $99 a year for a free app, so first launch needs one xattr command), and seek works by sending arrow keys because Apple locked down MediaRemote in 15.4. If anyone knows a better way to set the elapsed time of the now-playing app, I would love to hear it.

It is about 1,500 lines of Swift plus a small C shim. Feedback on gesture feel is the most useful thing you can give me.
