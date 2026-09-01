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

## 11. UI / UX & State Management

*(Applies to any project with a user-facing interface.)*

- **Color: roughly 60/30/10** — 60% neutral/background, 30% surface, 10%
  accent. Use semantic tokens (`bg-default`, `accent-primary`) rather than
  raw hex values scattered through components.
- **Grid & type: an 8-point spacing system** (8px, 16px, 24px…), a small
  type scale (~4 sizes), and two font weights. Body text around 16px.
- **Loading states are real, not generic.** Prefer component-specific
  skeletons and contextual spinners over a fake full-screen loading
  indicator that hides what's actually happening.
- **Error boundaries show human-readable messages.** Never leak stack
  traces, internal tokens, or raw error objects to the UI outside of an
  explicit debug mode.
- **Microcopy is clear and action-oriented.** "Save changes," not "Submit."
  Say what the action does, not a generic verb.

## 12. Style & Formatting

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

## 13. Documentation & Commit Discipline

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

## 14. Definition of Done

A feature or change isn't done until:

1. It works end-to-end (backend and frontend, where both apply) — not just
   the happy path.
2. Errors are handled explicitly and surfaced clearly, per §8.
3. Any new configurable value lives in config/settings, not hardcoded, per
   §7.
4. Relevant docs (README, user guide, API docs) are updated to reflect it,
   per §13.
5. The change is committed in small, reviewable increments with clear
   messages, per §13.

If a change doesn't meet all five, it's not finished — it's in progress.

## 15. Useful Commands (adapt per project)

```bash
# Python
black . && ruff check . --fix && flake8 .
pytest

# JS/TS
prettier --write . && eslint . --fix
npm test
```

---

*This document sets the standard for how code is written on projects that
reference it. Project-specific requirements (product scope, data models,
timelines) belong in that project's own PRD/README — this file stays
project-agnostic so it can be reused as-is elsewhere.*
