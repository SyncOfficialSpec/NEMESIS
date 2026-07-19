# GLYPH — PERDITION v4 design system

Status: ratified 2026-07-19 by a 3-judge design panel (unanimous, 42/44/42 vs SIGNAL 38/35/35, HALO 25/21/17).
DNA sources: Neverlose, Primordial, Fatality, Skeet, Syde / Linear, Geist, Raycast, Arc, Nothing OS, Teenage Engineering / Destiny 2, Cyberpunk 2077, Control.

## Concept

Industrial monochrome hardware. The menu is a precision instrument from the
Nothing OS / Teenage Engineering world: strict ink-and-white monochrome, one
alarm color spent on under 5% of pixels, RobotoMono part codes, LED-dot
indicators, raw-data values, and instant 0ms state changes as a philosophy.
Where CALIPER was a *machined* instrument (plates, seams, skeuomorphic depth),
GLYPH is a *printed* one (flat, gridded, honest).

## Laws (violating these = the redesign failed)

1. **Monochrome law.** All surfaces, text, strokes and icons come from one
   neutral step scale. The only hue on screen is the accent. Accent area stays
   under 5%: LED dots, active hairline, danger/confirm states, the boot mark.
2. **Instant law.** State changes are 0ms by default. Affordance comes from
   inversion and LEDs, not tweens. Structure (window, pages) may *arrive* with
   intent: one <100ms snap, then a card cascade (0.045s stagger, capped 10
   cards so the last lands by ~450ms). Hovers 80ms. Nothing idles, breathes,
   or loops.
3. **Flat law.** No shadows except ONE static baked drop behind floating
   layers (window, dropdowns, popovers, notifications). No translucency over
   translucency. Depth = tonal steps + inversion (white plate on ink ground).
4. **Part-code law.** Every structural element carries a RobotoMono code:
   sections `cfg–01`, elements auto-indexed `tgl–03` / `sld–01`, window
   version tag `prd–4.0.0`. Labels lowercase. Values raw-data (`120/360`).
5. **One tic.** RobotoMono is the voice for labels, codes and values. Inter is
   allowed only for long prose (paragraphs, notification body) where mono
   fatigues. No other fonts.

## Tokens

Neutral steps (generated, see theme engine):

| token | role |
|---|---|
| `N0` | window ground (ink, default #0C0C0D) |
| `N1` | sidebar / topbar ground |
| `N2` | card plate |
| `N3` | field / well / chip |
| `N4` | hover step |
| `N5` | hairline |
| `N6` | strong hairline / disabled text |
| `N7` | muted text |
| `N8` | secondary text |
| `N9` | primary ink/text (#F2F2F2) |
| `PAPER` | inversion plate (#F2F2F2) — overlays, active LED wash |
| `ACCENT` | alarm red (default #FF2D2D, user-retintable) |
| `ACC_DIM` | accent at low alpha for hairlines/washes |
| `GOOD` / `WARN` / `BAD` | status — monochrome-first; GOOD reuses ACCENT unless overridden |

Geometry: window radius 4, cards 3, controls 2, LED 0 (square). 1px hairlines
everywhere. Row height 34. Spacing on a 4px grid (4/8/12/16/24).

Type scale (RobotoMono): micro-code 10 Bold tracked +6%, label 12-13 Medium,
value 12 Medium tabular, header 13 Bold, prose 13 Inter. Mono below 11px is
banned (muddy raster — judge fix).

Motion: instant states; LED cue 70ms pop (scale 0.6→1 + alpha); window snap
<100ms; card cascade 0.045s stagger cap 10; page swap = 80ms crossfade;
dropdown/popover = instant open with 80ms plate-in; boot sequence once per
load.

## Theme engine (3 knobs, stolen from HALO/Linear)

`SetTheme{ base = "ink"|"paper", accent = Color3, contrast = 0..1 }` generates
the N-scale: base picks the two poles, contrast stretches the step spacing,
accent passes through with an auto dim variant. Legacy presets
(`Dark/Midnight/Abyss/Paper`) map to knob triples so the old API never breaks:
Dark → ink/red/0.5 family, Paper → paper/red/0.5, etc. Custom legacy theme
tables still accepted and snapped to the nearest steps.

## Signatures (the 5-second-clip identity)

1. **LED matrix.** Toggles/checkboxes are square LED wells: off = N3 well with
   N6 dead-dot; on = ACCENT dot with a 70ms pop. Status rows use 2x2 dot grids.
2. **Part codes everywhere.** Auto-indexed mono codes on every section and
   element, dim N7, left of the label.
3. **Registration marks.** Four 6px corner ticks (hairline) pinned outside the
   window corners, like crop marks. Zero tweens, pure identity.
4. **Dot-matrix boot.** Boot card shows a baked 5x7 dot-matrix "PERDITION"
   wordmark (baked PNG via tools/iconsgen pipeline), a scanline cascade down
   the window, and ONE 80ms glitch flicker (2 visibility flickers + 2px
   jitter) at the very start. Boot-only — per-toggle glitch would be
   screenshotted as a bug (judge fix). Setting to skip boot entirely.
5. **Raw-data footer.** Sidebar footer reads like instrument telemetry:
   `fps 60 · ping 42 · 12:03:44` mono tabular, LED heartbeat dot.

## Chrome

- Topbar: dot-matrix-flavored wordmark (text, not image, after boot), mono
  version tag `prd–4.0.0`, square glyph window controls (–, ×) as 22px hit
  boxes, hairline under-bar rule.
- Sidebar: tab rows = mono code + lowercase label + right LED dot (active =
  ACCENT pop, inactive = N6). No sliding indicator — instant inversion of the
  active row (N2 plate).
- Pages: cards on the 4px grid, section headers = 1px rule + `cfg–01` code +
  lowercase title, hairline under.
- Minimize: collapses to a compact instrument bar (wordmark + LED + fps).
- Overlays (modal, dropdown, notify, popovers): PAPER inversion plates with
  ink text + one static baked drop. Notifications stack top-right, square,
  hairline border, LED-coded severity (accent = info, red reserved for real
  errors via BAD).

## Risks (from judges, with mitigations)

- Mono lowercase below 11px rasters muddy → min 11px, Medium weight minimum.
- 0ms toggles read as "didn't register" → 70ms LED pop cue (not a tween of
  state, a one-frame acknowledgment).
- Ink/white at 2am is a flashlight → default base is INK (dark). Paper is a
  theme knob, not the default.
- Pure inversion flattens overlays → every floating layer gets the single
  baked drop + PAPER plate; dropdowns never sit directly on cards unraised.
- Long cascades feel sluggish → stagger capped (0.045s x 10 max).

## Build roadmap

1. Token foundation: TOKENS table, 3-knob engine, role-tag painting registry
   (replaces color-value re-theme walk), legacy preset adapter. Zero visible
   change.
2. Window shell: chrome per spec, registration marks, LED sidebar, instrument
   footer, minimize bar, boot sequence + dot-matrix wordmark asset.
3. Layout engine: 4px grid masonry, section header spec, page crossfade.
4. Components: every factory restyled (toggles/LED first, then inputs,
   dropdowns, pickers, charts, misc), overlays to PAPER plates.
5. Signatures polish: part-code pass, boot choreography, footer telemetry.
6. Sweep: live verify every element, perf audit, v4.0.0, README/showcase.
