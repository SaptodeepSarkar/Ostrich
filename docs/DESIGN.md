# Ostrich design language — "Pebble"

**Status:** active (2026-11-19) · **Applies to:** shell, lock, greeter, settings,
launcher, every popup.
**References:** `docs/reference/style/` (user photos),
[glyph-rice](https://github.com/Nebelung-cloud/glyph-rice) (GPL, inspiration only).
**Contracts:** `docs/CONTRACTS.md` §10 (components) and §10.1 (design tokens).

Ostrich should feel like **soft, inflated glass pebbles floating on a black
canvas**: bubbly, tactile, a little neon, never flat Material. The Material
palette still supplies the colours; this document supplies the *material*.

---

## 1. Five rules

1. **Everything floats.** Surfaces are detached pebbles with shadow and empty
   space around them. No full-bleed panels except the wallpaper and the
   greeter/lock backdrop.
2. **Light comes from the top-left.** One specular highlight per pebble, one
   soft rim light, one ambient glow tinted by the palette. Never two competing
   light sources.
3. **Colour is ambient, not fill.** Base surfaces stay dark/neutral; saturated
   colour lives in the glow, the rim, and a single accent element.
4. **Shape is a blob, not a rectangle.** Corner radii are large and continuous
   (`radius >= height/2` for pills, 28–40 px for cards). Corners should look
   inflated, not rounded-off.
5. **Motion is springy but short.** 180–240 ms, slight overshoot on press
   release, no bouncing carousels. Reduced motion removes all of it.

Anti-goals: flat Material cards, hard 1 px borders, neon-on-neon text, glass
panels that reduce text contrast, more than one accent per screen.

---

## 2. Materials

| Material | Use | Construction |
| --- | --- | --- |
| `solid` | bar, cards, buttons, settings rows | vertical gradient `surfaceContainerHigh → surfaceContainer`, 6–10% primary tint, 1 px inner top highlight |
| `glass` | popups, OSD, launcher panel | `solid` at 55–75% opacity + `MultiEffect` blur of the wallpaper behind, rim light at 20% |
| `iridescent` | clock, avatar, greeter dial, hero elements | multi-stop gradient `primary → secondary → tertiary` at low saturation, animated only on hover/unlock |
| `bubble` | icon buttons, dock items, small controls | near-circular pebble, tighter specular, stronger rim |
| `dot` | clock numerals, progress ticks, session dial | dot-matrix motif (glyph inspiration), always monochrome or single accent |

Material is chosen by role, not by page. A card is `solid` even on the launcher;
only the launcher *panel* may be `glass`.

### 2.1 Token additions

Design tokens extend the palette (they are derived, never hand-picked):

```qml
radiusPill: 999
radiusCard: 32
radiusControl: 20
pebbleTint: 0.08              // primary mixed into the surface
rimOpacity: 0.55
rimWidth: 1.0
specularOpacity: 0.22
glowOpacity: 0.35
glowRadius: 28
shadowOpacity: 0.45
shadowBlur: 32
shadowOffsetY: 10
pressScale: 0.96
hoverLift: 2
```

Exposed through `Metrics` (WS1) so every component shares them; settings can
scale `glowOpacity`, `shadowBlur`, and `pebbleTint` for a calmer look.

---

## 3. Component kit (additions to `CONTRACTS.md` §10)

| Component | API | Notes |
| --- | --- | --- |
| `Pebble.qml` | `material`, `radius`, `tint`, `glow`, `elevation`, `interactive`, default content | base surface; the only component allowed to draw its own shadow |
| `Bubble.qml` | `size`, `material`, `icon`, `checked`, `onClicked` | circular pebble for icons, dock, avatars |
| `PebbleButton.qml` | `text`, `icon`, `variant` (`solid`/`tonal`/`ghost`), `enabled`, `onClicked` | press scale + shadow collapse |
| `GlowRing.qml` | `value` 0..1, `thickness`, `glow`, `indeterminate` | radial progress for OSD, volume, session dial ticks |
| `DotMatrixText.qml` | `text` (digits, `:`, `-`), `dotSize`, `dotGap`, `color`, `glow` | Canvas-drawn 5×7 matrix; no font dependency |
| `Specular.qml` | `radius`, `tint`, `intensity`, `quality` | shared `ShaderEffect`; the only shader in the shell |
| `LoginSurface.qml` | `mode` (`lock`/`greeter`), `user`, `message`, `error`, `busy`, `onSubmit(text)` | shared by lock and greeter (WS12) |
| `UserBubble.qml` | `user`, `avatar`, `selected`, `onClicked` | greeter user picker |
| `SessionDial.qml` | `sessions`, `currentIndex`, `onSelected(index)` | radial session picker (greeter) |

Rules:

- Feature modules use these components; they do **not** write `ShaderEffect`,
  `MultiEffect`, gradients, or shadow stacks themselves.
- `Pebble`/`Bubble`/`Specular` must render acceptably without a GPU shader.
  Quality levels:
  - `low`: layered `Rectangle`s + `LinearGradient`, no blur, no noise;
  - `medium`: `Specular` shader + `MultiEffect` shadow;
  - `high`: shader + noise + animated iridescence + bloom.
- Set `appearance.pebbleQuality` (`low|medium|high`, default `high`) and
  `appearance.pebbleTint` (0..0.2). Low-end GPUs and remote sessions should use
  `medium`/`low` without losing the silhouette.

### 3.1 Sketch of the shader contract

```qml
// Specular.qml (API only; implementation owned by WS1)
ShaderEffect {
  property color base
  property color tint
  property real radius
  property real gloss      // 0..1, from Metrics.specularOpacity
  property real rim        // 0..1, from Metrics.rimOpacity
  property int quality     // 0=off, 1=simple, 2=full
  // fragment: vertical gradient, elliptical top-left highlight,
  // 1.5 px rim light on the top/left edges, faint inner shadow bottom-right,
  // optional value noise at 2% for a frosted feel.
}
```

The shader must be resolution-independent, never read outside its item, and have
a `quality: 0` path that draws nothing (component falls back to Rectangles).

---

## 4. Layout and density

- **Canvas:** pure `background` (near-black) with the wallpaper dimmed 25–35%
  behind windows; shell surfaces sit on top with 12–24 px gaps.
- **Bar:** a floating pill, 8–12 px from the screen edge, radius = height/2,
  `glass` material, grouped widget clusters separated by 8 px of air, not
  divider lines. Left cluster = workspaces, center = clock + media, right =
  status pebbles.
- **Popups:** `glass` pebbles anchored to their trigger, 12 px offset, 20–32 px
  padding, one primary action.
- **Settings:** sidebar of `Bubble`s + `solid` content cards on the canvas, no
  nested cards deeper than two levels.
- **Dock:** individual `Bubble`s (not one long bar), 6 px gaps, magnify on hover.
- **Lock/greeter:** full-bleed dark scene, one hero pebble element, everything
  else floats around it.

Spacing scale: 4, 8, 12, 16, 24, 32, 48. Font scale multiplies text only, never
pebble radii.

---

## 5. Typography and the dot motif

- UI text: `Theme.fontFamily` (default Inter/Noto Sans), weights 400/500/600.
  Never set pixel sizes directly; use `Theme.fontSize` tokens.
- Display numerals (clock, timers, battery percent on the lock screen): either
  the rounded display font (`Theme.displayFontFamily`) or `DotMatrixText`.
  Dot matrix is the signature motif inherited from the reference inspiration —
  use it for **one** element per screen.
- Letter spacing is slightly loose on labels (2–4%), tight on big numerals.
- Do not use more than two families on one surface.

---

## 6. Motion

| Interaction | Duration | Easing |
| --- | --- | --- |
| Hover | 120 ms | `Easing.OutCubic` |
| Press | 90 ms in, 220 ms out | `Easing.OutBack` (overshoot 1.05) |
| Popup open | 180 ms | `Easing.OutQuint`, opacity + 8 px translate |
| Popup close | 120 ms | `Easing.InCubic` |
| Workspace/window change | 220 ms | cross-fade, no slide |
| Greeter unlock | 400 ms | dial collapses into the clock pebble |

- No infinite animations except the OSD media equalizer and the “busy” spinner.
- Reduced motion (`appearance.reducedMotion`) sets every duration to 0 and
  disables shader noise/animation.
- Animations never block input; the item is interactive on the first frame.

---

## 7. Greeter and lock (shared "Aurora" scene)

Both surfaces share `LoginSurface` and the same composition, so login and unlock
feel like the same object waking up.

```
┌────────────────────────────────────────────────────────────┐
│  hostname · caps/num dots                    power pebbles │
│                                                            │
│              ╭──────────────────────╮                      │
│              │   giant pebble clock │                      │
│              ╰──────────────────────╯                      │
│                                                            │
│        ◜ session dial arc (greeter only) ◝                 │
│                                                            │
│              (avatar bubble)  username                    │
│              ╭──────────────────────────╮                  │
│              │ password pill  · · · ·  │                  │
│              ╰──────────────────────────╯                  │
│                     error / hint line                      │
│                                                            │
│                  [ unlock / sign in ]                      │
└────────────────────────────────────────────────────────────┘
```

- **Greeter:** giant clock (live, from `SystemClock`), user bubbles or a name
  field, `SessionDial` (sessions from `/usr/share/wayland-sessions/*.desktop`),
  power pebbles, caps/num indicators, greetd error line, staged fade-in on
  start (400 ms) unless reduced motion.
- **Lock:** same layout minus the session dial and user picker; shows battery,
  media (optional), and “locked” state. Wallpaper is the current one, blurred
  24–40 px and dimmed 35%.
- Backgrounds: animated iridescent blobs (`Specular`/`ShaderEffect`) or a static
  blurred wallpaper at `low` quality. Never a flat gradient alone.
- Failure feedback: pebble shakes horizontally 3×4 px, rim turns `error`, hint
  line appears; backoff is WS7's.
- Both surfaces must remain usable at 1024×768 and at 200% scale.

---

## 8. Accessibility and contrast

- Text always sits on `solid` or heavily scrimmed `glass`; minimum 4.5:1 against
  the *composited* background, not the token alone.
- Gloss and rim never cross text areas; the specular hotspot lives in the
  top-left corner of a surface, outside the label box.
- Focus is a 2 px outer glow in `primary` plus a 1 px `onSurface` ring — visible
  on black and on bright wallpapers.
- Every icon-only control has a tooltip and `Accessible.name`.
- `appearance.reducedMotion` and `appearance.highContrast` are first-class:
  high contrast raises rim/specular contrast and removes translucency.

---

## 9. Performance budget for the material

- One `Specular` shader instance per visible pebble is too many. `Pebble`
  should share a cached shader source and cap shader usage to **≤ 12 items per
  screen** at `high`; beyond that it falls back to gradients.
- `MultiEffect` blur only on `glass` surfaces, never animated per frame.
- Iridescent animation is a slow 8–12 s loop, paused when the window is not
  visible.
- Cold start budget is unchanged (PRD §6); the material must not add more than
  50 ms to first paint.
- Provide `OSTRICH_PEBBLE_QUALITY=low` as a debugging override.

---

## 10. Do / don't

Do:

- stack shadow → body gradient → inner highlight → rim → specular;
- tint shadows with the palette (`surface`/`primary`) instead of pure black;
- leave 12–24 px of canvas around every floating group;
- use one accent per screen (the “live” element).

Don't:

- draw a 1 px grey border on a pebble;
- put a pebble inside a pebble inside a pebble;
- animate blur radius or shadow blur per frame;
- use pure white `#fff` for highlights (use `onSurface` at 20–30%);
- copy the reference screenshots' layouts, numerals, or dial geometry verbatim.
