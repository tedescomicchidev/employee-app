# Design tokens (Phase 1 mockups)

Source of truth for the values used in the iPhone mockups (`mockups/index.md`). The mockups are drawn in
`project/ios.css` on the canvas; this file mirrors that stylesheet. Status: draft for human review.

Rules that win over this file: Apple HIG and system components (`docs/design/` conventions). Where a mockup
and a system component disagree, the system component wins and the deviation is reported in the PR.

No design system was supplied for this round, so these tokens are an iOS 26 baseline (system look, SF Pro),
not a brand. Replace the `tint` and the semantic colours when a brand system exists.

## 1. Frame and layout

| Token | Value | Note |
|---|---|---|
| Artboard | 390 x 844 pt | iPhone portrait, light appearance only in this round |
| Top inset | 54 pt | space left for the real status bar; none is drawn |
| Navigation bar | 48 pt high, 12 pt side padding | glass circle / capsule buttons, 44 pt targets |
| Floating tab bar | 64 pt high, 14 pt side inset, 22 pt from bottom, capsule | 4 tabs; managers get a 5th, "Freigaben" |
| Composer (agent) | 50 pt min height, 12 pt side inset, 24 pt from bottom, capsule | replaces the tab bar on chat screens |
| Content gutter | 16 pt (grouped lists, cards, banners) | large title text at 20 pt |
| Section header inset | 36 pt left, 18 pt top, 7 pt bottom | |
| List row | 56 pt min height, 16 pt padding, 12 pt gap | dense rows may use 50 pt |
| Touch target | >= 44 x 44 pt | A11Y-005 |
| Primary button | 50 pt high (card actions 48 pt) | capsule, full width |

## 2. Colour

Light appearance. Names are the CSS custom properties in `ios.css`.

| Token | Value | Use | Suggested native mapping |
|---|---|---|---|
| `bg` | `#F2F2F7` | screen background | `systemGroupedBackground` |
| `card` | `#FFFFFF` | grouped lists, cards, hero | `secondarySystemGroupedBackground` |
| `ink` | `#000000` | primary text | `label` |
| `ink2` | `#56565C` | secondary text, captions | `secondaryLabel` (check contrast) |
| `sep` | `rgba(60,60,67,.20)` | hairlines (0.5 pt) | `separator` |
| `fill` | `rgba(120,120,128,.16)` | chips, skeletons, disabled buttons, segmented track | `tertiarySystemFill` |
| `tint` | `#0A66E0` | actions, links, selected, agent user bubble | custom accent (see note) |
| `tint-s` | `rgba(10,102,224,.12)` | selected tab, soft buttons, range | tint at 12% |
| `red` / `red-s` | `#C9162B` / `rgba(215,0,21,.10)` | errors, destructive, rejected | accessible red |
| `grn` / `grn-s` | `#1B7A36` / `rgba(36,138,61,.14)` | success, approved | accessible green |
| `org` / `org-s` | `#9A4600` / `rgba(255,149,0,.18)` | pending, offline, partial, conflict | accessible orange |

Other fixed values: agent bubble `#E8E8ED`; toggle on `#1F8F3E`; placeholder `#6E6E73`; disabled label
`#85858B`; chevron `#8A8A90`; tab label `#505056`; holiday dot `#C25E00`. Banner text: offline `#6E3300`,
error `#8F0E1D`, info `#084DA8`, success `#12602A`.

Notes
- System blue `#007AFF` is about 4.0:1 on white and fails 4.5:1 for text, so `tint` is darkened.
- Status is never colour alone: every status chip carries an icon and a text label (A11Y-003).
- Contrast values above were chosen to target WCAG 2.2 AA but have not been measured with a tool yet.
- Dark mode, Increase Contrast and Reduce Transparency variants are not defined in this round.

## 3. Typography

Font stack: `-apple-system, "SF Pro Text", "SF Pro", system-ui, "Helvetica Neue", sans-serif`. On device this
is SF Pro through Dynamic Type text styles; the px values below are the default size only.

| Role | Size / line | Weight | Tracking | Text style |
|---|---|---|---|---|
| Hero number | 64 / 68 | 700 | +0.3 | custom (scales with Dynamic Type) |
| Large title | 34 / 41 | 700 | +0.4 | `largeTitle` |
| Screen headline (opt-in, detail) | 32-28 / 38-34 | 700 | +0.3 | `title` |
| Empty-state / sheet title | 22 / 28 | 600-700 | +0.2 | `title2` |
| Card title | 20 / 25 | 600 | +0.1 | `title3` |
| Body, list title, buttons | 17 / 22 | 400 / 600 | -0.4 | `body` / `headline` |
| Secondary | 15 / 20 | 400 | -0.4 | `subheadline` |
| Caption, section header | 13 / 18 | 400 / 600 | -0.1 | `footnote` |
| Tab label | 11 / 13 | 500 | 0 | `caption2` |
| Code (error codes) | 12 / 16 mono | 500 | 0 | monospaced `caption` |

Rules: sentence case everywhere; numbers tabular in time columns; Swiss orthography (ss, no ß); dates
`Do 24. Dez.`, times `09:00`, thousands separator `’`. All strings in German in this round; FR/IT/EN come
from the String Catalog (NFR-009).

## 4. Shape, depth, material

| Token | Value |
|---|---|
| Radius: grouped list / card | 26 pt |
| Radius: hero card | 30 pt |
| Radius: sheet | 40 pt (bottom sheet) / 38 pt top corners (full-height) |
| Radius: alert | 34 pt |
| Radius: button, pick chip, segmented | capsule (22-25 pt) |
| Radius: tab bar | 32 pt (capsule) |
| Radius: composer | 27 pt (capsule) |
| Radius: chat bubble | 22 pt, tail corner 6 pt |
| Radius: status chip | 12 pt (24 pt high) |
| Glass (bars, nav buttons, composer) | white 74-84% + blur 22-24 pt + saturate 180% + 0.5 pt edge + soft shadow |
| Shadow: floating bars | `0 10 32 rgba(0,0,0,.13)` |
| Shadow: confirm card | 0.5 pt edge + `0 10 28 rgba(0,0,0,.07)` |
| Scrim | black 28-30% |

Use real system materials on device; the glass values only approximate Liquid Glass in the mockups.

## 5. Components

| Component | Variants / states | Notes |
|---|---|---|
| Grouped list row | title, subtitle, trailing value, chevron, unread dot, avatar, icon badge | unread = dot + semibold title |
| Status chip | Ausstehend (orange, clock), Genehmigt (green, check), Abgelehnt (red, x), language (grey / blue), count (blue) | always icon + text |
| Pick chip | off / on (44 pt, tint fill when on) | audience selection, multi-select |
| Segmented control | 44 pt high | Anträge / Team, language |
| Button | primary, soft (`sec`), neutral (`pl`), destructive (`red`), disabled (`dis`) | busy state = spinner + label |
| Banner | offline (orange), error (red), info (blue), success (green) | one per screen, below the title |
| Skeleton | line, block | no shimmer required; announce "Lädt" |
| Empty state | icon disc 76 pt, title, one sentence, optional action | |
| Error state | red icon disc, plain cause, retry, correlation id + code behind "Details" | codes in mono |
| Toggle | on / off / dimmed (system notifications denied) | |
| Calendar | day cell 44 pt; states: weekend, holiday (dot), range, start/end, existing request, conflict | non-calendar alternative: "Datum eingeben" (A11Y-005) |
| Event row | time column 56 pt, title, place + attendee count, conflict chip | free block = tinted row |
| Chat bubble | user (tint, white text), agent (`#E8E8ED`) | agent text is quoted data when from content |
| Quoted data block | dashed border, caption "Zitat aus der Mitteilung" | FR-ANN-005 |
| Tool status line | spinner (working) / check (done) / warning (failed) + one phrase | |
| Confirm card | header (action), title, key-value payload, Abbrechen + primary, footnote with validity | see below |
| Alert / sheet | alert: title, message, stacked capsule buttons; sheet: grabber, title, content | cancel confirm, reject reason, consent |

Confirm card (FR-AUTH-006)
- Shows the exact payload that will be executed and says so: "Genau dieser Inhalt wird ...".
- States: proposal (primary enabled, validity countdown), executing (spinner, cancel disabled, composer
  disabled), success (green ring, outcome line from the tool result, link to the classic detail), failed
  (red ring, reason code, nothing changed), expired (muted, buttons disabled, offer to re-propose).
- Typed text such as "ja, mach das" never confirms; only the tap on the card does.
- Actions: cancel left (neutral), confirm right (primary, wider).

## 6. Icons

Stroke icons, 24 pt grid, 2 pt stroke, rounded caps; sizes 15 / 20 / 24 / 30 / 36. Drawn as masks so they take
`currentColor`. On device use SF Symbols with the same meaning:

| Mockup | Meaning | SF Symbol (suggested) |
|---|---|---|
| mega | Aktuell / announcements | `megaphone` |
| sun | Ferien | `sun.max` / `beach.umbrella` |
| cal | Woche / calendar | `calendar` |
| sl | Mehr / settings | `slider.horizontal.3` |
| appr | Freigaben | `checkmark.circle` |
| pen | compose | `square.and.pencil` |
| chat | assistant | `bubble.left` |
| plus, up, back, fwd | add, send, navigation | `plus`, `arrow.up`, `chevron.left`, `chevron.right` |
| check, x, warn, info | status | `checkmark`, `xmark`, `exclamationmark.triangle`, `info.circle` |
| woff | offline | `wifi.slash` |
| lock | no access, consent | `lock` |
| ppl, person, store, globe, clock, bell, doc, rf, stop | audience, own data, place, online, pending, reminder, text, retry, cancel | `person.2`, `person`, `storefront`, `globe`, `clock`, `bell`, `doc.text`, `arrow.clockwise`, `stop.fill` |

No emoji as UI glyphs. No custom speech or mic button: voice input is the system keyboard dictation (A11Y-006).

## 7. Accessibility hooks to carry into SwiftUI

- Labels on every icon-only button (the mockups use `aria-label` as the stand-in).
- Loading regions announce "Lädt"; the confirm card moves focus on appear and announces the result.
- Layouts must reflow at AX5; none of the screens may rely on fixed heights for text.
- Respect Reduce Motion, Bold Text, Increase Contrast, Reduce Transparency (glass falls back to opaque `card`).

## 8. Open items

- Brand colour and brand typeface: none supplied; `tint` is a placeholder.
- Dark appearance and AX5 variants for the screenshot matrix are not drawn yet.
- HR-CONFIRM values shown in mockups (25 days, 3 carry-over, holiday list) are placeholders, not policy.
