# Theme Spec — Neobrutalism (PRD §14)

The deliverable §14.4 asks for: tokens defined once, consumed everywhere, never
hand-styled per screen. Source of truth is `lib/ui/theme/tokens.dart`; this
document explains the intent so it doesn't get relitigated (PRD §14).

## Two intensity levels (PRD §14.2)

| Level | Border | Shadow offset | Where |
|---|---|---|---|
| `NbIntensity.full` | 5px | 6px hard | Scan accept/reject state; primary CTAs (submit top-up, confirm reversal, generate bill) |
| `NbIntensity.restrained` | 3px | 3px hard | Admin data surfaces — member tables, menu calendar, settings forms, purchase lists |

A screen never chooses a raw border or shadow value — it passes an `NbIntensity`
to a shared widget (`NbSurface`, `NbButton`).

## Colour — 60 / 30 / 10 (PRD §14.3, CLAUDE.md §11.4)

- **60% ground:** `NbColors.surfaceBg` (warm off-white)
- **30% surface:** `NbColors.surface` / `surfaceMuted`
- **10% accent:** `NbColors.accent` (blue) — reserved for the single most
  important action on a screen (Von Restorff). Status colours (`accept`,
  `reject`, `warn`) count toward the 10% and appear only on status surfaces.

Every accent/status colour is documented in `tokens.dart` with the text colour
that clears **WCAG AA** on it. Those are the only pairings the UI may use.

## Never colour alone (PRD §14.3, WCAG POUR "Perceivable")

Accept/reject and grace/pending states always carry, in addition to colour:

- a distinct **icon** (check / cross / clock),
- a distinct **border weight** (`full` vs `restrained`),
- a **text label**.

## Grid & type (PRD §14.3, CLAUDE.md §11.4)

- Spacing: 8-point scale only — `NbSpace.{xs,sm,md,lg,xl,xxl}` = 4/8/16/24/32/48.
- Type: 4 sizes (`display`, `heading`, `body`, `label`), 2 weights (400 / 700),
  body = 16px. Monospaced family for the blocky look, system-mono fallback.
- Radius: always `BorderRadius.zero`.

## Accessibility invariants (CLAUDE.md §12.2 — apply regardless of theme)

- Touch targets ≥ 48px (`NbButton` enforces `minHeight: 48`).
- Visible focus state: inputs switch to a 5px accent border on focus.
- Semantic widgets, labelled form fields, `Semantics(button: true)` on
  tap targets that aren't real buttons.
