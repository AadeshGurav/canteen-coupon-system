# CLAUDE.md — Engineering Standards

This document defines how code gets written on projects that reference it. It
applies across projects and languages unless a project's own docs explicitly
override a section. It is written for an AI coding agent (Claude Code or
similar) as much as for a human contributor — treat it as binding, not
aspirational.

---

## 1. Identity & Mindset

You are an expert software engineer who values elegance, simplicity, and
maintainability above all else. Think in systems, not just features — a
change should make sense in the context of the whole codebase, not just the
file it touches. Prefer working *within* the actual, documented capabilities
of the frameworks and libraries already in use rather than building hacky
workarounds for undocumented behavior or fighting the tool you're using.

## 2. Before Writing Code — Required Procedure

1. **Index the relevant parts of the codebase.** Don't guess at structure —
   look.
2. **Read and understand what's actually there** before proposing a change,
   including existing patterns, naming conventions, and prior decisions.
3. **Fully understand the request.** If something is ambiguous in a way that
   would change the approach, ask — don't silently assume.
4. **Formulate a plan** for anything non-trivial: a debugging investigation,
   an architectural shift, or a change touching multiple files. No scattered,
   incremental trial-and-error committed straight to the codebase.
5. **Get approval before major changes.** Present significant architectural
   decisions — new dependencies, schema changes, restructuring — for
   confirmation before implementing them, not after.
6. **Then implement** the most elegant, maintainable solution that fits the
   existing system.

## 3. Core Principles

- **Beautiful > ugly. Explicit > implicit. Simple > complex. Flat > nested.**
- **Readability counts.** Code is read far more often than it's written —
  optimize for the next person (including future-you) understanding it fast.
- **Errors never pass silently**, unless the silence is explicit and
  intentional (and commented as such).
- **One obvious way to do it.** Don't introduce a second pattern for
  something the codebase already has a convention for.
- **If it's hard to explain, it's probably a bad idea.** Design should be
  explainable in a sentence or two.
- **Comment intent, not mechanics.** The code already says *what* it does;
  comments should say *why*, especially for non-obvious decisions or
  trade-offs.
- **Code as prose.** Minimize the cognitive load needed to follow a function
  top to bottom.

## 4. Architecture & Infrastructure

- **SOLID & DRY**, applied pragmatically — extract genuinely repeated logic,
  but don't abstract prematurely on the guess that something *might* repeat.
- **Don't reinvent what the stack already provides.** Check for built-in
  support (rate-limiting, queues, caching, validation, auth) in the
  frameworks already in use before adding a new dependency or hand-rolling
  infrastructure.
- **Prefer deployment simplicity.** Favor a single, unified deployable unit
  over microservice sprawl unless there's a concrete reason (team boundary,
  independent scaling need, genuine isolation requirement) for splitting it.
- **Fix issues at the source, permanently.** Configuration, setup scripts,
  and infra definitions should reflect the fix — never patch a running
  instance by hand and leave the source out of date.
- **Separate concerns cleanly.** Keep a clear boundary between user-facing
  interfaces and internal API/service/engine layers. A UI component
  shouldn't reach past its API boundary into internal logic.

## 5. Code Structure & Quality

- **File size is a signal, not just a rule.** As a rough ceiling, a file
  pushing past ~300 lines is usually doing more than one job — split it into
  smaller, domain-specific modules along natural seams rather than
  arbitrarily.
- **Functions should be small, testable, and do one clear thing**
  (single responsibility). Prefer passing dependencies in over reaching for
  internal imports or global/mutable state.
- **Naming is descriptive and intent-revealing.** Avoid `data`, `temp`,
  `info`, `util`, `helper` as standalone names — say what the thing actually
  is. Use a verb-noun pattern for functions: `load_config_file()`,
  `calculate_average_weight()`, `reverse_scan()`.
- **Isolate failure.** A single component or feature failing shouldn't take
  down unrelated functionality. Degrade gracefully, and make the failure
  visible (logged, surfaced) rather than swallowed.

## 6. Testing

- **New logic gets tests**, especially anything with a decision branch
  (validation, business rules, edge cases) — not just the happy path.
- **Tests should be fast and independent.** Avoid tests that depend on
  execution order or on state left over from another test.
- **Test behavior, not implementation.** A test that breaks every time you
  refactor internals without changing behavior is testing the wrong thing.
- **A bug fix gets a regression test** where practical, so it can't silently
  come back.

## 7. Security & Configuration

- **No secrets in source.** API keys, tokens, and credentials live in
  environment variables or a secrets manager, never hardcoded or committed —
  and never logged.
- **Config lives in config, not in code.** Anything an operator or admin
  might reasonably need to change (limits, thresholds, feature flags,
  timing windows, business rules that could shift) belongs in environment
  config or a settings store — not as a constant buried in application
  logic.
- **Validate input at the boundary.** Use the framework's built-in
  validation (schema/type validation, request parsing) rather than manual
  ad-hoc checks scattered through business logic.
- **Least privilege by default.** New endpoints, tokens, and integrations
  get the minimum access they need, not broad/admin access for convenience.

## 8. Error Handling & Observability

- **Errors are specific, not generic.** Surface what actually went wrong,
  not just "something went wrong" — both in logs and, where appropriate, to
  the end user.
- **Log with enough context to debug without reproducing.** Include the
  relevant identifiers (user, request, entity) in log lines, not just a
  message.
- **User-facing errors are human-readable.** Never expose stack traces,
  internal error codes, or raw exception text to an end user in normal
  operation — translate to a clear, actionable message.
- **Treat logging as a first-class feature when the system needs to be
  operable by someone other than the original developer.** If the person
  running it day-to-day isn't the one who built it, the logs are their main
  debugging tool — design them accordingly.

## 9. Development Workflow & Setup

- **Zero-touch setup.** A new environment should be installable and runnable
  with one command and no manual intervention — a single entry point
  (`Makefile`, setup script) is worth the upfront investment.
- **Trust hot-reloading where the stack provides it.** Don't reflexively
  suggest restarting a dev server for changes the tooling already picks up
  automatically.
- **Test incrementally against real, live dev data** within one running
  instance rather than juggling disconnected dev/test environments, unless
  the project specifically needs that separation.
- **Branch with intent.** Use descriptive, prefixed branch names
  (`feature/`, `fix/`, `arch/`) and keep experimental or architectural work
  off `main` until it's reviewed.

## 10. Dependency Management

- **Every new dependency is a decision, not a default.** Prefer the
  standard library or something already in the project over adding a new
  package for a small amount of functionality.
- **Pin versions deliberately** and know why an upgrade is happening when it
  happens — don't bulk-upgrade without reading what changed.
- **Remove what you stop using.** Unused dependencies, dead code paths, and
  orphaned config are cleanup debt — take it out in the same change that
  makes it unused, not "later."

## 11. UX & UI: Psychology-Grounded Design Principles

*(Applies to any project with a user-facing interface.)* Interfaces aren't
judged by developer intuition — human perception, memory, and decision-making
follow measurable, studied patterns. Treat what follows as grounded defaults,
not decoration, and cite the underlying principle in a design/PR discussion
rather than just asserting a preference.

### 11.1 Usability Heuristics (Nielsen & Molich, 1990; Nielsen, 1994)

Derived from a factor analysis of 249 real usability problems and unchanged
in substance since 1994, because the human factors behind them haven't
changed. Apply all ten as a standing checklist for any interactive feature:

1. **Visibility of system status** — always show what's happening, with
   feedback within a reasonable time (ideally immediate). A user who doesn't
   know the system's state can't predict its next move or trust it.
2. **Match between system and the real world** — use the user's language and
   mental model, not internal jargon or database field names. Follow
   real-world conventions and natural order.
3. **User control and freedom** — every flow needs a clearly marked
   "emergency exit": undo, cancel, back. Don't trap people in a multi-step
   process with no way out.
4. **Consistency and standards** — don't make users wonder if different
   words or actions mean the same thing. Maintain both internal consistency
   (within this product) and external consistency (platform/industry
   convention) — people spend most of their time on *other* products, and
   those set their expectations (Jakob's Law, §11.2).
5. **Error prevention** — the best error message is the one that never had
   to appear. Prefer constraints and good defaults over relying on a warning
   after the fact.
6. **Recognition rather than recall** — don't make people remember
   information from one screen to use on another. Keep options, labels, and
   context visible where the decision is actually made.
7. **Flexibility and efficiency of use** — accommodate both novices and
   experts: sensible defaults for the former, shortcuts/accelerators for the
   latter, without punishing either group.
8. **Aesthetic and minimalist design** — every extra element competes with
   the ones that matter. Cut anything that isn't earning its place on the
   screen.
9. **Help users recognize, diagnose, and recover from errors** — plain
   language, no error codes, state precisely what went wrong and what to do
   next.
10. **Help and documentation** — the best system needs none, but when it's
    needed, make it searchable, contextual, and task-focused, not a wall of
    text.

### 11.2 Cognitive & Behavioral Laws

These come from experimental psychology and behavioral economics, not design
tradition — they describe how people actually perceive, decide, and
remember. Interfaces that ignore them create friction whether or not anyone
on the team can articulate why.

- **Jakob's Law** — users spend most of their time on other products, so
  they arrive with those products' expectations already baked in. Deviating
  from a familiar pattern has a real cognitive cost; only break convention
  as a deliberate, justified trade, not a stylistic whim.
- **Fitts's Law** — the time to reach a target is a function of its size and
  the distance to it. Make frequent or high-stakes touch/click targets large
  and close to where the user's attention already is (mobile guidance
  commonly cites ~44–48px minimum touch targets); don't shrink primary
  actions to fit decoration.
- **Hick's Law** — decision time increases with the number and complexity of
  choices available. Reduce options at the point of decision; if a flow
  genuinely needs many choices, stage them (progressive disclosure) instead
  of presenting them all at once.
- **Miller's Law, refined by Cowan** — Miller's famous "7±2" (1956) described
  *chunks*, not raw items, and it's the single most-misquoted number in UX.
  Later work (Cowan, 2001) found that once chunking and rehearsal tricks are
  controlled for, working memory holds closer to **3–4 chunks**, not seven.
  The practical rule for both: group related information into meaningful
  chunks (a formatted phone number, a labeled form section) rather than a
  long flat list — and don't treat "under seven items" as a safe number on
  its own; chunking quality matters more than raw item count. This applies
  most strongly to *recall* (remembering something with no reference);
  *recognition* tasks (scanning a visible list) tolerate more items.
- **Postel's Law (the robustness principle)** — be liberal in what you
  accept from users (flexible input parsing, forgiving formats), conservative
  in what you show or send back (clear, consistent, validated output).
- **Peak-End Rule** — people judge an experience largely by its most intense
  moment and its ending, not the average of every step along the way.
  Invest disproportionately in the peak (the moment something succeeds) and
  the end (confirmation, receipt, completion state) of a flow, not just the
  middle steps.
- **Aesthetic-Usability Effect** — users perceive more attractive designs as
  more usable, even when objective usability is identical, and are more
  forgiving of minor friction inside a well-designed interface. This is a
  real reason to invest in visual polish — but never a substitute for fixing
  an actual usability problem underneath it.
- **Von Restorff Effect (isolation effect)** — an item that visually stands
  out from its surroundings is disproportionately more noticeable and
  memorable. Use this deliberately for the one action that matters most on a
  screen (the primary call-to-action) and avoid it everywhere else — if
  everything is emphasized, nothing is.
- **Serial Position Effect** — people remember the first and last items in a
  list or sequence better than the middle. Put the most important items at
  the start or end of a list or flow, not buried in the middle.
- **Tesler's Law (conservation of complexity)** — every process carries an
  irreducible amount of complexity; it can be moved, never eliminated. The
  real question is never "how do we remove this complexity" but "who
  absorbs it — the system or the user" — and the system should absorb it
  whenever it can.
- **Doherty Threshold** — productivity rises sharply when a system responds
  to a user within roughly 400ms; beyond that, users disengage or lose their
  train of thought. Optimize *perceived* responsiveness (optimistic UI,
  skeleton states, §11.4) as much as actual backend latency.
- **Goal-Gradient Effect** — motivation to complete a task increases as
  people get closer to the goal. Visible progress indicators ("step 3 of 4")
  measurably increase completion rates, especially near the end of a flow.
- **Zeigarnik Effect** — people remember interrupted or incomplete tasks
  better than completed ones, and feel a pull to finish them. Useful for
  onboarding/setup flows ("your profile is 80% complete") — but see the
  ethical note below before leaning on it.

**Ethical note.** Several of the laws above (goal-gradient, Zeigarnik, von
Restorff) are also the exact mechanics behind dark patterns — engineered
urgency, manufactured incompleteness, manipulative emphasis. Use them to
make genuinely useful actions easier to notice and complete, never to
pressure a user into something that isn't in their own interest. If a
pattern only works *because* the user doesn't fully realize what's
happening, don't ship it.

### 11.3 Gestalt Principles of Visual Perception

From Gestalt psychology (Wertheimer, Koffka, and Köhler, early 20th
century): the mind perceives organized wholes, not a collection of isolated
elements. These explain *why* a layout reads as organized or chaotic before
a user consciously processes any of the text on it.

- **Proximity** — elements placed close together are perceived as related.
  Use spacing itself to group a form's related fields, rather than relying
  only on borders or dividers.
- **Similarity** — elements that share color, shape, or size are perceived
  as belonging to the same category or having the same function. Keep
  visual treatment consistent for elements that behave the same way (all
  destructive actions look alike, all links look alike).
- **Common region** — elements sharing an enclosed area (a card, a bordered
  section) read as a group even more strongly than proximity alone.
- **Figure-ground** — people instinctively separate a foreground "figure"
  from its background. Make sure the thing that matters right now (a modal,
  the active tab, primary content) reads unambiguously as the figure through
  contrast, not just position.
- **Continuity** — the eye follows the smoothest path through aligned
  elements. Align related elements on a shared axis instead of scattering
  them, so the eye can track a natural line through a list or flow.
- **Closure** — the mind fills in gaps to perceive a complete shape. This
  can be used deliberately (a partially visible next card in a carousel
  implies "more to scroll") — but don't let *unintentional* visual gaps
  create confusing false shapes.
- **Common fate** — elements that move or change together are perceived as
  one group. Animate related elements in sync, not independently, when they
  represent a single logical unit.

### 11.4 Practical Interface Standards

- **Color: roughly 60/30/10** — 60% neutral/background, 30% surface, 10%
  accent. Use semantic tokens (`bg-default`, `accent-primary`) rather than
  raw hex values scattered through components.
- **Grid & type: an 8-point spacing system** (8px, 16px, 24px…), a small
  type scale (~4 sizes), and two font weights. Body text around 16px.
- **Loading states are real, not generic.** Prefer component-specific
  skeletons and contextual spinners over a fake full-screen loading
  indicator that hides what's actually happening (this is also what makes
  the Doherty Threshold, §11.2, survivable when a real response takes
  longer than 400ms).
- **Error boundaries show human-readable messages.** Never leak stack
  traces, internal tokens, or raw error objects to the UI outside of an
  explicit debug mode.
- **Microcopy is clear and action-oriented.** "Save changes," not "Submit."
  Say what the action does, not a generic verb.

## 12. Universal & Inclusive Design

### 12.1 The Seven Principles of Universal Design (Mace et al., NC State Center for Universal Design, 1997)

Universal design's founding insight — from Ron Mace, an architect who used a
wheelchair — is that designing for the full range of human ability from the
start, rather than a default design plus a later "accessibility retrofit,"
produces a better product for *everyone*, not only people with disabilities.
Apply all seven to digital products, not just physical spaces:

1. **Equitable use** — the same experience for everyone wherever possible,
   an equivalent one where identical isn't possible. Don't build a degraded
   "accessible version" as an afterthought — that's segregation, not equity.
2. **Flexibility in use** — accommodate a range of preferences and
   abilities: offer more than one way to complete a task where reasonable
   (an action reachable by mouse, keyboard, and touch alike).
3. **Simple and intuitive use** — usable regardless of the person's
   experience, language, literacy, or current cognitive load, independent
   of unnecessary complexity. This overlaps directly with the usability
   heuristics in §11.1.
4. **Perceptible information** — necessary information must reach the user
   regardless of ambient conditions or sensory ability: redundant coding
   (never color alone — see §12.2), sufficient contrast, compatibility with
   assistive technology.
5. **Tolerance for error** — minimize the consequences of accidental or
   unintended action: confirmations before destructive actions, easy undo,
   forgiving input parsing (Postel's Law, §11.2).
6. **Low physical effort** — efficient and comfortable to use with minimal
   fatigue: adequately large touch targets (Fitts's Law, §11.2), minimal
   required precision, sensible defaults that reduce repetitive input.
7. **Size and space for approach and use** — usable regardless of the
   user's body size, posture, or mobility — or, for digital products,
   regardless of their device, screen size, input method, or assistive
   hardware.

### 12.2 Accessibility — WCAG (W3C Web Content Accessibility Guidelines)

The internationally recognized, legally-referenced standard (informing the
ADA, Section 508, and equivalents worldwide), organized around four
principles — POUR:

- **Perceivable** — information and UI components must be presentable in
  more than one way. Never encode meaning in color alone (a meaningful share
  of users — commonly cited around 1 in 12 men — can't reliably distinguish
  certain colors); pair color with an icon, label, or pattern. Provide text
  alternatives for non-text content. Meet minimum contrast ratios for text
  and meaningful UI elements.
- **Operable** — every interactive element must be reachable and usable via
  keyboard alone, not just mouse or touch. No keyboard traps. Give users
  enough time to complete an action, or a way to extend it. Focus order
  should follow visual/logical order.
- **Understandable** — text and interaction should be readable and
  predictable. Consistent navigation and identification across a product.
  Label errors clearly and suggest how to fix them (this is also usability
  heuristic #9, §11.1).
- **Robust** — content must work reliably across current and future
  browsers, devices, and assistive technologies — use semantic HTML and
  standard components before reaching for custom-built ones that assistive
  tech can't interpret.

**Practical minimum for every project:** semantic HTML elements over generic
`<div>`s with click handlers, visible focus states, alt text on meaningful
images, labeled form fields, sufficient color contrast, and full keyboard
operability. Treat WCAG AA conformance as the working default, not an
eventual nice-to-have.

## 13. Internationalization & Localization (i18n / l10n)

Products not built with internationalization in mind from the start
accumulate hardcoded strings, locale-tied formatting, and layouts with no
room for translated text — all expensive to retrofit later. Build
i18n-ready even for a single-locale launch; the upfront cost is small and
the retrofit cost is not.

- **Never concatenate translatable strings.** `"You have " + count + "
  items"` breaks under different word orders and pluralization rules — use
  full-sentence keys with named placeholders instead (ICU MessageFormat or
  equivalent), e.g. `{count, plural, =0 {No items} =1 {One item} other {#
  items}}`.
- **Pluralization is not binary.** Different languages have different
  plural categories — CLDR defines up to six (zero/one/two/few/many/other;
  Arabic uses all six, and Russian's "few" covers a different numeric range
  than English's "one"). Use a library that implements CLDR plural rules
  rather than hand-rolled `if (count === 1)` logic.
- **Design for text expansion.** Translated text commonly runs 30–40%
  longer than the English equivalent. Don't hardcode fixed-width containers
  around text; test layouts against long-language content, not just
  English.
- **Support right-to-left (RTL) languages structurally, not cosmetically.**
  Use the HTML `dir` attribute and CSS logical properties
  (`margin-inline-start` instead of `margin-left`) so layouts mirror
  correctly for Arabic, Hebrew, and similar languages, instead of
  hardcoding left/right.
- **Never bake text into images.** Text in images can't be translated,
  resized, or read by screen readers — keep text as text and layer it over
  graphics if needed.
- **Use locale-aware formatting for dates, numbers, and currency**, never
  hand-rolled string formatting — a platform `Intl` API (or equivalent)
  correctly handles that `1,234.56` in the US is `1.234,56` in Germany, and
  that date order varies by locale (MM/DD vs. DD/MM vs. YYYY-MM-DD).
- **Store data in one canonical form, display it in the user's local
  convention.** This applies to dates/times (store UTC, display local),
  numbers, and sort order — locale-aware collation (`Intl.Collator` or ICU
  collation) sorts correctly per language; naive byte/ASCII sort misorders
  almost every non-English alphabet.
- **Keep translatable strings out of code, in resource files** (`.json`,
  `.po`, `.arb`, or equivalent), with context comments for translators — a
  string reused in two different UI contexts in English may need two
  different translations elsewhere.
- **Test with pseudo-localization before real translations exist.** Piping
  source strings through accented, padded pseudo-text surfaces hardcoded
  strings, clipped layouts, and concatenation bugs immediately, without
  waiting on translators.
- **This isn't only a frontend concern.** Backend-generated content —
  emails, PDF documents, error messages, notifications — needs the same
  locale awareness as UI text, or it becomes the thing that breaks the
  moment the product is used in a second language.

## 14. Style & Formatting

- **Automate formatting; don't hand-enforce it.** Apply formatting/linting
  to changed files as part of the workflow, not as a manual review nitpick.
- **Tooling standard (adapt to the project's language):**
  - Python: `black` (project line-length setting, commonly 88 chars) →
    `ruff` for linting/quick fixes → `flake8` for deeper static analysis.
    Fix issues rather than suppress warnings.
  - JS/TS: `prettier` for formatting → `eslint` for linting, with the
    project's configured rule set enforced, not selectively ignored.
- **Formatting details:** consistent indentation (follow the language/
  project convention), consistent quote style, one blank line between
  logical blocks, imports sorted and unused imports/variables removed.

## 15. Documentation & Commit Discipline

- **Update docs in the same change that changes behavior.** A README or
  user guide that's out of sync with the code is a bug in the change, not a
  follow-up task.
- **Commit small and often.** Each commit should represent one coherent,
  reviewable change with a message describing what changed and why. Avoid
  bundling unrelated changes into one large commit — it's harder to review,
  harder to revert, and harder to reason about later.
- **Write commit messages for the next reader**, not just for yourself right
  now. A future contributor (or agent) should be able to understand the
  history without re-deriving the reasoning.

## 16. Definition of Done

A feature or change isn't done until:

1. It works end-to-end (backend and frontend, where both apply) — not just
   the happy path.
2. Errors are handled explicitly and surfaced clearly, per §8.
3. Any new configurable value lives in config/settings, not hardcoded, per
   §7.
4. Any user-facing surface meets the working accessibility minimum, per
   §12.2.
5. Relevant docs (README, user guide, API docs) are updated to reflect it,
   per §15.
6. The change is committed in small, reviewable increments with clear
   messages, per §15.

If a change doesn't meet all six, it's not finished — it's in progress.

## 17. Useful Commands (adapt per project)

```bash
# Python
black . && ruff check . --fix && flake8 .
pytest

# JS/TS
prettier --write . && eslint . --fix
npm test
```

---

## References

The principles in §11–§13 are drawn from published research and established
standards, not house opinion. For further reading:

- Nielsen, J., & Molich, R. (1990). *Heuristic evaluation of user
  interfaces.* Proc. ACM CHI'90.
- Nielsen, J. (1994). *10 Usability Heuristics for User Interface Design.*
  Nielsen Norman Group.
- Yablonski, J. (2020/2024). *Laws of UX: Using Psychology to Design Better
  Products & Services.* O'Reilly.
- Miller, G. A. (1956). *The Magical Number Seven, Plus or Minus Two.*
  Psychological Review, 63(2).
- Cowan, N. (2001). *The Magical Number 4 in Short-Term Memory: A
  Reconsideration of Mental Storage Capacity.* Behavioral and Brain
  Sciences, 24(1).
- Wertheimer, M.; Koffka, K.; Köhler, W. — foundational Gestalt psychology
  (early 20th century), as applied to design via modern Gestalt-in-UX
  literature.
- Mace, R., et al. (1997). *The 7 Principles of Universal Design.* Center
  for Universal Design, North Carolina State University.
- W3C Web Accessibility Initiative — *Web Content Accessibility Guidelines
  (WCAG) 2.2.*
- W3C Internationalization Activity — *i18n best practices*; Unicode CLDR
  — locale, plural, and collation data.

*This document sets the standard for how code is written on projects that
reference it. Project-specific requirements (product scope, data models,
timelines) belong in that project's own PRD/README — this file stays
project-agnostic so it can be reused as-is elsewhere.*
