# 流光 · Liquid Glass

The design system Caduceus is built on, and the rules that keep it coherent.
Source: the `Caduceus DS C - Liquid Glass` and `Caduceus Motion Prototype`
documents in Claude Design. Code lives in `flutter_app/lib/design/`.

The idea in one line: **the content plane is solid, and every piece of chrome
is a sheet of glass floating over it.** Light passes through the glass, the
edges catch a highlight, and the colour behind is refracted. Deep space, one
aurora, one piece of brass.

## The rules that are not negotiable

**Long-form text never sits on glass.** Glass carries controls — rows,
toolbars, inputs, menus. The moment something is meant to be *read*, it lands
on opaque `Palette.slate`. This is the single easiest way to ruin the design,
and it was ruined exactly once: the transcript rendered over the drifting
aurora, and a table of results had coloured light moving underneath it. See
`ColoredBox` in `console_view.dart` — that plane is what all the glass is over.

**One brass control per screen.** `BrassButton` is the only solid fill in the
system. A second one on the same screen halves the meaning of both; if a screen
seems to need two, it has two primary actions and needs a decision instead.

**The aurora is background only.** Azure, violet and jade appear at full
strength in `Aurora` and in small indicators (`StatusDot`, `ContextMeter`).
Never as a foreground fill, never behind text.

**Hierarchy is material, not colour.** A selected session row is a *thicker
sheet*, not a tinted rectangle. A popover is thicker still. `Glass.thin` →
`Glass.regular` → `Glass.thick` is the whole vocabulary for "further forward".

**Text hierarchy is opacity: 100 / 70 / 50 / 34.** Four steps, from
`InkLevel`. Every "just slightly dimmer" one-off is how a palette turns to mud.

**Mono means the machine said it.** Addresses, tokens, model ids, paths,
elapsed times. `glm-5-2-260617` vs `…260618` must be readable character by
character.

**Glass never nests.** A `GlassPanel` inside another one draws its tint,
border and rim but opens no second `BackdropFilter` — enforced in the material
itself, so no call site can get it wrong. Nesting was both the expensive
mistake and the ugly one: the inner filter blurs what the outer already
blurred, the aurora turns to flat grey haze, and a drawer with a search pill, a
button and eight rows spent eleven filters against a budget of two. Pinned by
`test/glass_budget_test.dart`.

**Entrances belong to surfaces, not rows.** A scrolling list must sit inside a
`StaggerScope`, or every row replays its entrance each time it scrolls back
into view — `ListView.builder` disposes what leaves the viewport and builds it
fresh on return. Pinned by `test/entrance_recycle_test.dart`.

**Nothing keeps an outgoing session mounted.** Switching fades the arriving
transcript in and drops the old one at once (`SessionFade`). An
`AnimatedSwitcher` holds the outgoing child for the length of the transition,
and switching away and back inside that window puts two views of one
conversation on screen — duplicate keys immediately, and both of them
attaching that conversation's single scroll controller.

**The serif appears three times.** Welcome, empty session, consequential
confirmation. It is what gives the product somewhere to pause; spend it
anywhere else and it stops meaning anything. `serifDisplay`.

## Motion

Three curves, four durations, in `Motion`:

| | duration | curve | for |
|---|---|---|---|
| Standard | 200 ms | `(.32,.72,0,1)` | hover, selection, switches — 90% of everything |
| Emphasized | 320 ms | `(.2,0,0,1)` | drawers, palette, switching session |
| Exit | 160 ms | `(.4,0,1,1)` | every dismissal |
| Ambient | ~2.4 s loop | ease-in-out | "this is alive" and nothing else |

Disappearing is always half the speed of appearing. Nobody should wait for a
dismissal.

Motion here is **the physics of a material, not decoration**:

- **Thickness transition** — a popover opens by the glass getting *thicker*
  (`GlassPanel.thickness` driven by a controller), not by fading in.
- **Rim light** — a running turn lights the composer's edge. It replaces a
  "generating…" label outright: no line of text, no translation.
- **Press** — down to .94, released on a `SpringSimulation`, overshooting to
  ~1.02. Interrupt a spring and it carries its velocity; a curve cannot.
- **Sheen** — a 4.5 s highlight across the brass button. Too slow to read as
  animation; reads as light on something polished.
- **Stagger** — list items 24 ms apart, capped at 8 so long lists do not trail.
- **Sheets arrive from their edge** — 底部面板从下推入. `showPanel` uses a
  `PopupRoute` rather than `showGeneralDialog` for one reason: it can have a
  *reverse* duration, and disappearing is always half the speed here. A centred
  dialog on a Mac slides from nowhere, because it is not attached to an edge.
- **The icon leads the row by 40 ms** — 制造"手快"的错觉. A hovered row tints over
  120 ms and its dot answers in 80, so the dot has already arrived while the
  background is still travelling. Nothing is faster; the row just stops feeling
  like it is catching up with the pointer.
- **A question grows out of the corner it was typed in** — `GrowFromComposer`
  scales from `bottomEnd`, not the centre. A centred scale is a bubble that
  appeared; this one was sent.
- **手势跟随** — the drawer, the back gesture and every sheet follow the finger
  1:1, and release decides by *velocity or distance*: a fast flick dismisses
  even when it covered barely any ground, which is how the gesture is actually
  performed. `PullToDismiss` is the one implementation — two sheets that
  dismiss differently is worse than either rule alone.
- **Overshoot is a number, not a curve's leftovers** — `GlassSwitch`'s thumb
  goes exactly 3 points past. `easeOutBack` gives a tenth of its range for
  free, which on 18 points of travel is 1.8; `_NormalisedOvershoot` rescales
  it so the design's number is the one on screen.

### Ambient motion can always be switched off

`ambientAllowed(context)` is false when the user asked their OS to reduce
motion, when the material is degraded, or while something is scrolling. Every
loop in the system honours it, which is only safe because **no state, progress
or affordance is ever expressed by an ambient loop alone**.

Widget tests freeze it globally in `test/flutter_test_config.dart`: an endless
loop makes `pumpAndSettle` hang rather than fail, which is the worst way for a
suite to report anything.

## Degraded material

`Materials.degraded` swaps every sheet for solid slate with a 1 px edge and
turns the aurora off. Backdrop blur is a real GPU cost, and the design allows
at most two blurred layers on screen. **Sizes, radii, durations and curves are
unchanged** — the app feels identical and only looks cheaper. That is the point:
the handling should not depend on the hardware.

The one rule that follows from it: an unselected list row is a flat tint, never
a `GlassPanel`. Twenty rows would be twenty backdrop layers.

## Where things are

```
lib/design/tokens.dart      palette, ink levels, glass levels, radii, motion
lib/design/glass.dart       GlassPanel, SlatePanel, the blur+saturate filter
lib/design/aurora.dart      the four drifting lights and the grain
lib/design/theme.dart       ThemeData, the type ramp, mono() and serifDisplay()
lib/design/press.dart       Pressable, Sheen, HoldToConfirm, PullToDismiss
lib/design/components.dart  BrassButton, MorphButton, GlassSwitch, Segmented, Staggered
lib/widgets/panel_frame.dart Panel — a dialog on a Mac, a pulled sheet on a phone
```

Fonts are bundled, not fetched: all three faces are SIL OFL, and a typeface
that arrives a second late reflows the whole transcript.

## What the design asks for and this app deliberately does not do

**进入会话 — the title flying from the row into the nav bar.** A `Hero` flight
needs a route push, and the phone shell does not push for a session: the
conversation *is* the screen and sessions live behind a drawer, which was a
deliberate earlier decision (making the list the screen put the thing people
came for one tap away and the thing they rarely need permanently in front).
There is no journey for the title to make. A Hero was written and removed
after confirming it could never fire; faking the flight by hand would be
animation for its own sake.

**多窗口 — two sessions side by side, drag to split.** Out of scope for now.

**05 FAB 放射展开 — the floating action button that fans its children out on a
radius.** There is no FAB. The one primary action per screen is already a
brass pill in the composer or the rail, where it sits next to what it acts on;
adding a floating circle in the corner to give the animation a home would be
building a control to justify a transition.

## The device's own hardware

The composer's ＋ sheet draws the prototype's four tiles — 拍照 · 图库 · 文件 ·
录像 — and the microphone beside send. All of it goes through `lib/capture.dart`
rather than straight to a plugin, for two reasons: every one of these is a
platform channel that does not exist under `flutter test`, and "did the
composer ask for a photo, and did the bytes reach the session" is worth being
able to answer without a camera.

**The microphone types.** There is no audio channel to the agent, so a voice
*message* would be a button that looks like it worked. Dictation puts words in
the field, where they can be read and corrected before they are sent.

**Camera tiles are hidden where there is no camera.** macOS has no
`image_picker` camera implementation; a tile that opens nothing is worse than a
tile that is not there.

**The usage strings are not optional.** iOS terminates the process the first
time one of these APIs is touched without its `NS…UsageDescription`, so the
four in `ios/Runner/Info.plist` and the two in the macOS one are load-bearing,
as is `com.apple.security.device.audio-input` in both macOS entitlements files
— without it the recogniser returns nothing, silently.

## What the design asks for and the server cannot do

The connection mock shows four ways in — QR pairing, a 6-digit pair code,
manual entry, and mDNS discovery on the LAN. The Hermes gateway exposes 130
methods and **none of them is a pairing or discovery API**. Only manual entry
is implemented; the rest would mean inventing a protocol the server does not
speak.

## Where a loop stops

Every ambient loop honours `ambientAllowed`, and every one of them also has a
**chosen resting frame**. Stopping in place is its own bug: the status dot
frozen at .45 reads as greyed out rather than as a state, the sheen frozen
mid-sweep is a bright stripe stuck across the brass, and a caret frozen
mid-blink says the answer ended.

## Verifying it

There is no Simulator window on this machine (this Xcode has no
`Developer/Applications`), so `integration_test/design_tour_test.dart` drives
the app to each surface and holds it while `simctl io screenshot` runs
alongside. It pumps continuously during a hold — a single long `pump` produces
one frame at the end, which is how the command palette once came back from a
screenshot looking like an empty sheet when its rows were merely mid-entrance.

Running it rewrites `FLUTTER_TARGET`; run `flutter build ios` afterwards. See
`integration_test/ios_touch_test.dart`.
