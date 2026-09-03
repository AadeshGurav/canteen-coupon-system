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

### 4.1 Architectural defaults

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

### 4.2 Backend design patterns — how to use this catalogue

The patterns in §4.3–§4.7 are language-agnostic and mostly framework-
agnostic. Two rules govern all of them:

1. **A pattern is an answer to a specific failure or change, not a
   decoration.** Before adopting one, state the concrete question it
   answers: *what happens when this exact thing fails, or changes?* If
   there's no answer, the pattern is premature. Distributed-systems
   patterns in particular exist because **things fail partway through,
   constantly** — that's the whole subject matter.
2. **Patterns don't remove complexity; they relocate it somewhere you can
   manage it** (Tesler's Law again, §11.2). Every one below has a stated
   cost. Adopt it knowing the cost, or don't adopt it.

Systems should start simple — a well-factored monolith, straightforward
persistence, timeouts, and a cache — and take on coordination, consistency,
and resilience patterns as real scale and real failure modes arrive.
Starting at the endpoint of that progression is the most expensive mistake
in this section.

### 4.3 Structural patterns — organizing the backend

- **Layered (n-tier)** — controller → service → repository → database.
  The right default for most projects: everyone understands it instantly,
  and it's enough structure for the majority of applications. Its weakness
  is that the domain ends up depending on the persistence layer, so
  framework and DB concerns leak upward over time.
- **Hexagonal / Ports & Adapters (Cockburn)** — business logic sits in the
  center; everything external (DB, HTTP, message broker, third-party API)
  is an interchangeable adapter plugged into a port the core defines.
  Dependency inversion means the adapter depends on the core, never the
  reverse. *Use when* the application is business-logic heavy, has
  multiple or evolving integration points, or is a large monolith you
  intend to keep for years. *Cost:* more indirection, more mapping code,
  a real learning curve. *Don't* impose it on a small, narrow service
  where there's barely any domain logic to protect — the boilerplate
  outweighs the benefit. Clean Architecture is the same idea with more
  prescribed layers; pick one and don't mix vocabularies.
- **Modular monolith ("modulith")** — one deployable unit, internally
  divided into modules with enforced boundaries (each module owns its data
  and exposes a narrow public surface; everything else is
  package-private/internal). **This is the recommended default for new
  systems of nontrivial size**, and it is the honest expression of
  "deployment simplicity" in §4.1: you get the boundary discipline that
  makes later extraction possible, without paying distributed-system costs
  before you have distributed-system problems.
- **Microservices** — only with a concrete justification: an independent
  scaling profile, a hard isolation/compliance boundary, or genuinely
  separate teams needing independent release cadence. "It's more modern"
  and "it'll scale better someday" are not justifications. Every service
  boundary you add is a network call that can fail, a deployment to
  coordinate, and a transaction you can no longer do atomically.
- **Strangler Fig** — the migration pattern. Put a routing layer in front
  of a legacy system and move capability across one slice at a time,
  retiring old code as each slice lands. Always prefer this to a big-bang
  rewrite; rewrites tend to fail because they must hit a moving target.

### 4.4 Domain & application patterns

- **Repository** — an interface that expresses persistence in domain
  terms (`find_active_subscribers()`), hiding the query mechanics. Keeps
  the domain testable without a database. *Cost:* an extra layer; don't
  add one that merely forwards to the ORM verbatim with no domain
  vocabulary of its own — that's ceremony, not abstraction.
- **Unit of Work / transaction boundary** — one explicit place per
  operation where a business transaction commits or rolls back. Define
  the boundary consciously; transactions that open in a controller and
  close somewhere in a repository are where the hardest data bugs live.
- **Service / Use-case objects** — one object or function per business
  operation, orchestrating domain objects and ports. Keeps controllers
  thin and makes the system's capabilities enumerable by reading a
  directory listing.
- **Value objects** — small immutable types for concepts with rules
  (`Money`, `EmailAddress`, `DateRange`). They make invalid states
  unrepresentable and pull validation out of scattered `if` blocks, which
  directly serves §3's "explicit over implicit."
- **Domain events** — the domain announces that something happened
  (`OrderPlaced`) rather than calling every interested party itself. This
  is what lets a new consumer be added without touching the producer.
- **Anti-Corruption Layer** — a translation boundary between your model
  and an external/legacy model, so their vocabulary and quirks don't
  infect your domain. Mandatory when integrating a third-party API whose
  shape you don't control.
- **Specification** — composable, named query/validation predicates
  (`ActiveSubscription().and(InTrial())`) instead of boolean-flag
  parameters proliferating across query methods.

### 4.5 Data & consistency patterns

- **Idempotency** — the single highest-value pattern in this section. A
  retried request must not execute twice. The client sends a unique
  `Idempotency-Key`; the server stores the result against that key with a
  TTL and returns the stored result on repeat. GET/PUT/DELETE are
  idempotent by definition; **POST and PATCH need it explicitly.** Any
  operation that moves money, sends a message, or creates a record must
  be idempotent — networks time out and clients retry, always.
- **Transactional Outbox** — solves the dual-write problem. When a service
  must update its database *and* publish an event, those are two
  independent I/O operations that can fail separately, leaving the system
  inconsistent. Instead, write the event to an `outbox` table **in the same
  database transaction** as the business change; a relay process polls the
  outbox and publishes to the broker. **Use this whenever a service
  publishes events** — it's not an advanced pattern, it's the correct
  default.
- **Saga** — a business operation spanning several services, where each
  step is a local transaction and failure is handled by *compensating*
  transactions rather than rollback. Note that compensation is a
  **semantic reversal, not an undo**: a refund is not the same as the
  payment never happening, and the design must acknowledge that. Two
  styles: *choreography* (services react to each other's events; fine for
  3–4 steps, hard to follow beyond that) and *orchestration* (a
  coordinator drives the flow; preferred for anything complex, because the
  workflow is readable in one place).
- **CQRS** — separate the write model from the read model, so reporting
  and dashboards don't compete with transactional writes. *Use when* reads
  and writes have genuinely different shapes or load profiles. *Cost:*
  eventual consistency between the two, which the UI must then represent
  honestly (§11.1 heuristic 1). Don't apply it to a CRUD screen.
- **Event Sourcing** — store the sequence of events as the source of
  truth and derive state from it. Powerful for auditability and temporal
  queries; expensive in schema evolution, tooling, and mental model.
  **Adopt only when audit history is a hard requirement**, not for
  general use. Usually paired with CQRS and Outbox.
- **Cache-Aside** — read from cache, on miss read the source and populate.
  The default caching strategy. Rules: every cached entry gets an explicit
  TTL; **never serve authoritative values from cache** (validate prices at
  checkout against the source of truth); have a stated invalidation
  strategy before shipping, not after the first stale-data incident.
- **Optimistic concurrency** — version/ETag on the record, `If-Match` on
  the write, `409`/`412` on conflict. Prefer this to pessimistic locking
  for user-facing edits; it makes lost updates visible instead of silent.

### 4.6 Resilience & integration patterns

These are what keep a system standing when a dependency degrades. Adopt
the first three on **every** outbound call, not selectively.

- **Timeouts on every network call.** An unbounded call is a resource leak
  waiting for traffic. Nothing — DB, cache, HTTP, queue — is exempt.
- **Retry with exponential backoff and jitter**, and only for *transient*
  errors. Retrying a `400` is a bug. Retry without jitter creates
  synchronized retry storms.
- **Circuit Breaker** — after a failure threshold, stop calling a
  degraded dependency and fail fast (closed → open → half-open →
  closed). The distinction that matters: **retries are for transient
  blips; circuit breakers are for sustained degradation.** Using retries
  *without* a breaker during a real outage amplifies the outage.
- **Bulkhead** — isolate resource pools per dependency so one slow
  downstream can't consume every connection/thread and take the whole
  service with it. This is §5's "isolate failure" expressed in
  infrastructure.
- **Rate limiting** — token bucket (allows bursts), sliding window (more
  precise), or fixed window (simplest, but permits double-rate bursts at
  window edges). Return `429` with `Retry-After` and the
  `RateLimit-*`/`X-RateLimit-*` headers so clients can behave well.
- **Dead-letter queue** — messages that fail repeatedly go somewhere
  visible and replayable, never into a silent discard or an infinite
  redelivery loop.
- **Graceful degradation** — decide, per feature, what the system does
  when a dependency is down: serve stale, serve partial, or disable that
  feature with an honest message. Never let a non-critical dependency
  fail the whole request (§5, §8).
- **Backpressure** — under overload, shed or queue deliberately rather
  than accepting everything and collapsing. Accepting work you can't
  complete is worse than rejecting it clearly.
- **Health checks** — separate *liveness* (is the process alive?) from
  *readiness* (can it serve traffic?). Conflating them causes orchestrators
  to restart healthy-but-warming instances.

### 4.7 API design contract

Applies to any HTTP API this project exposes. Decisions here are
expensive to change later, so make them on day one.

- **Model resources as nouns; let HTTP methods carry the verb.**
  `POST /orders`, not `POST /createOrder`. Return accurate status codes —
  **never `200 OK` with an error in the body.**
- **Standardize errors on RFC 9457 Problem Details**
  (`application/problem+json`, with `type`/`title`/`status`/`detail`/
  `instance` plus extension members). One error shape across the whole
  API, machine-readable, no ad-hoc strings. This is §8 ("errors are
  specific, not generic") in wire format.
- **Version from day one.** URI versioning (`/v1/`) is explicit and easy
  to test and cache; header versioning is cleaner but harder to operate.
  Bump for removed/renamed fields, changed types, or breaking request
  changes — **not** for added optional fields, new endpoints, or fixes.
- **Paginate every collection endpoint**, without exception. Prefer
  **cursor pagination** — offset pagination degrades badly at depth
  (`OFFSET 100000` scans and discards 100,000 rows) and drifts when the
  underlying data changes mid-traversal.
- **Idempotency keys on all unsafe operations** (§4.5).
- **Deprecate on a schedule, machine-readably** — announce, mark the
  endpoint deprecated in the spec and headers, give a documented sunset
  date, and only then remove.
- **The spec is the contract.** Maintain OpenAPI (or the protocol's
  equivalent) as a first-class artifact, generated or validated in CI —
  not written once and left to drift. Per §15, it updates in the same
  change that changes behavior.

### 4.8 Choosing, and what not to do

| Problem | Reach for |
| --- | --- |
| Service updates its DB and must publish an event | Transactional Outbox |
| Multi-service operation needing rollback | Saga (orchestrated if >4 steps) |
| Client may retry a mutating request | Idempotency keys |
| Reads starving writes, or very different read shapes | CQRS |
| Audit history is a hard requirement | Event Sourcing (+ CQRS, Outbox) |
| Flaky or slow downstream | Timeout + retry/backoff + circuit breaker + bulkhead |
| Read-heavy, tolerant of slight staleness | Cache-aside with explicit TTL |
| Concurrent edits to the same record | Optimistic concurrency (ETag/version) |
| Replacing a legacy system | Strangler Fig |
| Business-logic-heavy core, many integrations | Hexagonal / Ports & Adapters |
| Nontrivial new system, one team | Modular monolith |

**Anti-patterns to name and refuse:**

- **Distributed monolith** — services that must be deployed together and
  call each other synchronously in a chain. All of the cost of
  microservices, none of the benefit. The most common outcome of splitting
  a system too early.
- **Shared database between services** — kills the boundary it pretends to
  create. Each service owns its data.
- **Chatty synchronous call chains** — A calls B calls C calls D inside one
  request. Latency and failure probability compound. Make it async, or
  merge the services.
- **Retry without idempotency** — a duplicate-charge generator.
- **Pattern cargo-culting** — CQRS on a CRUD form, event sourcing for a
  settings table, a message broker for two components in the same process.
  Per §3, if it's hard to explain why the pattern is here, it shouldn't be.
- **Business logic in controllers, ORM models, or database triggers** —
  logic scattered across the layers that were supposed to be boundaries.

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
  visible (logged, surfaced) rather than swallowed. At the infrastructure
  level this is bulkheading and graceful degradation, per §4.6.

## 6. Testing

- **New logic gets tests**, especially anything with a decision branch
  (validation, business rules, edge cases) — not just the happy path.
- **Tests should be fast and independent.** Avoid tests that depend on
  execution order or on state left over from another test. Speed is a
  correctness issue in disguise: a suite slow enough to skip stops being
  a safety net (§18.1).
- **A flaky test is worse than no test.** Random failures train the team
  to ignore failures, which destroys the signal the suite exists to
  provide. Fix it or delete it — never re-run and move on.
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
  message. Propagate a correlation/trace ID across every service and
  queue hop — in a system with more than one moving part, that ID is the
  difference between debugging and guessing (§4.6).
- **User-facing errors are human-readable.** Never expose stack traces,
  internal error codes, or raw exception text to an end user in normal
  operation — translate to a clear, actionable message. For APIs, the
  wire format of this rule is RFC 9457 Problem Details, per §4.7.
- **Treat logging as a first-class feature when the system needs to be
  operable by someone other than the original developer.** If the person
  running it day-to-day isn't the one who built it, the logs are their main
  debugging tool — design them accordingly.

## 9. Development Workflow & Setup

- **Zero-touch setup.** A new environment should be installable and runnable
  with one command and no manual intervention — a single entry point
  (`Makefile`, setup script) is worth the upfront investment. Treat
  clone-to-running in under ten minutes as the target (§18.1).
- **Trust hot-reloading where the stack provides it.** Don't reflexively
  suggest restarting a dev server for changes the tooling already picks up
  automatically.
- **Test incrementally against real, live dev data** within one running
  instance rather than juggling disconnected dev/test environments, unless
  the project specifically needs that separation.
- **Branch with intent.** Use descriptive, prefixed branch names
  (`feature/`, `fix/`, `arch/`) and keep experimental or architectural work
  off `main` until it's reviewed.
- **Keep a real device in the loop for anything user-facing.** A browser's
  responsive emulator does not reproduce mobile browser-chrome behavior,
  touch accuracy, virtual-keyboard layout, or GPU limits — verify on an
  actual mid-range phone before calling a UI change done (§11.6.9).

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
  and close to where the user's attention already is; don't shrink primary
  actions to fit decoration. Note the refinement that matters in practice:
  above roughly 40px, *spacing between targets* affects tap error rate more
  than target size does. See §11.6.5 for the working sizes, spacing
  defaults, and reachability rules.
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
- **Define the color system in OKLCH, not hex/RGB/HSL.** OKLCH
  (`oklch(L C H)` — Lightness 0–1, Chroma ~0–0.4, Hue 0–360°) is a
  perceptually uniform color space: equal numeric steps in L, C, or H
  produce equal *perceived* steps, regardless of hue. HSL doesn't have this
  property — a "50% lightness" blue and a "50% lightness" yellow don't read
  as equally bright, and shifting HSL lightness on a hue like blue visibly
  drifts it toward purple. OKLCH hue stays visually constant across the
  full lightness range, which is what makes it reliable for building tints,
  shades, and multi-step scales programmatically instead of hand-picking
  each stop.
  - **Generate tonal scales by holding hue and chroma fixed and stepping
    lightness** (e.g. `oklch(0.98 0.02 250)` → `oklch(0.20 0.05 250)` for a
    10-step primary scale). This is what makes OKLCH-driven scales look
    coherent where an equivalent hand-tuned HSL ramp usually doesn't.
  - **Author semantic tokens in OKLCH** (`--color-bg-default`,
    `--color-accent-primary`) so lightness/chroma/hue can each be adjusted
    independently — e.g. dark mode as a lightness inversion of the same
    hue/chroma pair, rather than a hand-picked parallel palette.
  - **Use OKLCH chroma to check accessible contrast**, not just visual
    inspection — because L in OKLCH tracks perceived lightness directly, an
    OKLCH-based contrast/APCA check is a more reliable proxy for WCAG
    contrast (§12.2) than eyeballing HSL or hex values.
  - **Ship P3-gamut-aware colors where the design calls for genuinely vivid
    accents** — OKLCH can address the wider Display P3 gamut in addition to
    sRGB, so a color that looks washed out in sRGB hex can be authored
    accurately in OKLCH. Provide an sRGB (hex/rgb) fallback via CSS
    `@supports`/color-gamut media features for older browsers, since native
    OKLCH support is Chrome 111+, Firefox 113+, Safari 15.4+.
  - **Don't hand-roll conversions.** Use the platform's native `oklch()`
    CSS function or a maintained color library (Culori, Colorjs.io) for
    hex/rgb ↔ OKLCH conversion and gamut clamping — manual conversion math
    is error-prone and easy to get subtly wrong at the gamut boundary.
- **Grid & type: an 8-point spacing system** (8px, 16px, 24px…), a small
  type scale (~4 sizes), and two font weights. Body text around 16px —
  and never below 16px on form inputs, per §11.6.3. Size in `rem` and
  scale fluidly with `clamp()` rather than stepping at each breakpoint
  (§11.6.3).
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

### 11.5 Visual Theme Catalogue

A theme is a *skin over a system*, never a substitute for one. Pick one
deliberately at the start of a project, write it down, and apply it through
the token layer (§11.4) — don't let a style leak into components as
one-off shadow and color values. Every theme below is described the way it
exists in the wild, then constrained to comply with the rest of this
document. **Where a theme's native form conflicts with §11.4, §12.1, or
§12.2, this document wins and the theme bends.**

#### 11.5.0 The theme contract (applies to every theme below)

Any theme adopted on a project must satisfy all of these. A theme that
can't is not a theme we ship.

1. **Expressed as tokens, not as component CSS.** A theme is a set of
   values for the same semantic token names (`--color-bg-default`,
   `--color-surface-raised`, `--radius-card`, `--shadow-raised`,
   `--border-width-card`). Swapping themes should mean swapping a token
   file — if it means editing components, the theme was implemented wrong.
2. **Authored in OKLCH** per §11.4, with sRGB fallbacks. Depth and
   elevation are expressed as *lightness* steps on a fixed hue/chroma,
   which is precisely the problem OKLCH solves.
3. **WCAG AA is the floor, not a target** (§12.2): 4.5:1 for body text,
   3:1 for large text and meaningful UI boundaries — measured against the
   *effective composited* background, not the token color in isolation.
   This is the rule that kills most decorative themes, and it is not
   negotiable for a stylistic reason.
4. **Build the solid, opaque version first.** Translucency, blur, texture,
   and glow are a layer added on top of an interface that already works
   without them. If the flat version is unreadable, the effect was hiding
   a hierarchy problem, not solving one.
5. **State is never carried by the effect alone.** Hover, focus, selected,
   disabled, error — each needs a change that survives with all decoration
   stripped (§12.2 "never color alone" extends to "never shadow alone,"
   "never blur alone," "never glow alone"). Visible focus rings are
   mandatory in every theme, including the ones whose whole aesthetic is
   "no borders."
6. **Respect user preferences as first-class inputs**, not edge cases:
   `prefers-reduced-motion`, `prefers-reduced-transparency`,
   `prefers-contrast`, `prefers-color-scheme`, and `forced-colors`. Each
   should degrade the theme to a plainer, higher-contrast variant that
   still works.
7. **Performance is part of the theme.** GPU-heavy effects
   (`backdrop-filter`, large `box-shadow` stacks, animated gradients) are
   budgeted and tested on the low end of the target device range, not just
   on the developer's machine — the Doherty Threshold (§11.2) doesn't care
   how good the blur looks.
8. **Jakob's Law applies to themes too** (§11.2). An unusual visual
   language has a real cognitive cost. It's worth paying for a marketing
   site, a portfolio, or a brand-forward product; it is rarely worth paying
   for an internal tool, an admin panel, or anything a user is in for eight
   hours a day.
9. **The theme is designed at 360px first, not scaled down to it**
   (§11.6). Decorative depth, oversized type, and dense ornament all cost
   more on a small screen than a large one — a theme that only resolves at
   desktop width is not a theme this project can use.

---

#### 11.5.1 Flat / Modern Minimalism — *the default*

**What it is.** No simulated depth. Solid fills, clear type hierarchy,
generous whitespace, hierarchy carried by size/weight/spacing rather than
ornament. Modern flat ("flat 2.0") permits subtle shadows purely to signal
elevation, not to imitate a material.

**Use it when:** you don't have a specific reason to use something else.
Dashboards, SaaS, admin tools, internal software, anything data-dense or
long-session. It is the cheapest to build, the easiest to keep accessible,
and the least likely to look dated in three years.

**Token recipe (OKLCH).**
- Background `oklch(0.99 0.002 250)` / dark `oklch(0.18 0.01 250)`
- Surface `oklch(0.97 0.004 250)` — one lightness step from background
- Border `oklch(0.90 0.01 250)`
- Text primary `oklch(0.25 0.02 250)`, secondary `oklch(0.52 0.02 250)`
- Accent `oklch(0.58 0.17 250)` with hover at `L −0.05`, active at
  `L −0.10`, same C and H
- Radius 8px; shadows minimal (`0 1px 2px oklch(0 0 0 / 0.06)`)

**Failure mode to avoid.** Flatness that removes affordance — if a user
can't tell what's clickable, "minimal" has become "ambiguous." Nielsen #8
(§11.1) says cut what isn't earning its place; it does not say cut the
signals that tell people what to do.

---

#### 11.5.2 Swiss / International Typographic

**What it is.** Minimalism's stricter ancestor: a visible modular grid,
one neutral grotesque typeface at several sizes, asymmetric layout, flush-
left ragged-right text, near-monochrome palette with a single accent, and
generous negative space treated as an active element.

**Use it when:** content-led products — editorial, documentation, marketing,
data journalism, portfolios. Excellent for anything where reading is the
primary task.

**Constrained form.** Maps almost perfectly onto our existing rules: the
8-point grid (§11.4) *is* the modular grid, and Gestalt continuity and
proximity (§11.3) are what make it read as ordered. Keep to ~4 type sizes
and 2 weights per §11.4 — Swiss discipline is about restraint within a
scale, not about having many.

**Token recipe (OKLCH).** Near-zero chroma neutrals
(`oklch(0.98 0.001 90)` → `oklch(0.20 0.005 90)`), a single high-chroma
accent (classic Swiss red ≈ `oklch(0.58 0.21 27)`), hairline rules at
`oklch(0.85 0.005 90)`, radius 0–2px, no shadows.

**Failure mode to avoid.** Beautiful at desktop width, broken on mobile.
Test the grid at 360px and 320px before committing (§11.6.9), and watch
for text expansion (§13) shattering a tightly-set column.

---

#### 11.5.3 Material Design (Material 3 / "Expressive")

**What it is.** Google's system: flat surfaces plus *purposeful* elevation
(a documented z-scale), a defined motion language, a tonal palette
generated algorithmically from a source color, and a large prebuilt
component library.

**Use it when:** Android-first or cross-platform products, or any team that
needs a complete system rather than a look — Material ships the tokens,
the components, the a11y semantics, and the motion spec together. This is
Jakob's Law (§11.2) working in your favor on Android.

**Constrained form.** Material's tonal-palette generation is conceptually
the same operation as §11.4's OKLCH scale generation — prefer generating
the tonal steps in OKLCH so the palette is perceptually even, then map to
Material's role tokens (`primary`, `on-primary`, `surface-container`).
Use Material's role names as our semantic tokens rather than inventing a
parallel set.

**Failure mode to avoid.** Half-adopting it — taking the visual style but
not the elevation rules or motion spec — produces something that looks
like Material and behaves like nothing. Adopt the system or don't.

---

#### 11.5.4 Glassmorphism (and Apple's Liquid Glass)

**What it is.** Translucent, background-blurred panels with a fine light
border, floating over a colored or image backdrop — frosted glass. Liquid
Glass (Apple, 2025–26) is the refractive, more physically-modelled
evolution of it. This is currently the most durable of the "depth" styles
because its depth is *informational* — it tells you what's above what.

**Use it when:** overlays and chrome — modals, notification toasts,
sidebars, navigation bars, media players, floating cards — over a
deliberately designed backdrop. Strong fit for iOS/macOS-targeted products
and consumer apps.

**Constrained form — this is the theme our rules bend the most.**
- **Glass is for chrome and overlays, never for primary content areas.**
  Body copy and data tables sit on solid surfaces. Selective use is now
  the standard approach, not a compromise.
- **A semi-opaque fill goes *behind* the blur, not instead of it.** Blur
  alone does not guarantee contrast — it softens a background without
  bounding it. Target a fill opacity high enough that composited text
  clears 4.5:1 *against the worst-case backdrop*, not the demo backdrop.
- **Cap blur strength.** Keep `backdrop-filter: blur()` moderate
  (roughly ≤12–16px); very heavy blur is both a GPU cost and a
  motion/sensory issue for some users.
- **Limit concurrent glass surfaces** — a handful on screen, not a stack.
  Nested glass-on-glass is a contrast problem you cannot reason about.
- **`prefers-reduced-transparency` and `prefers-contrast` must swap the
  glass for a solid surface**, matching what the OS accessibility settings
  already do natively. Also provide a solid `@supports not
  (backdrop-filter: blur(1px))` fallback.
- **Test dark mode and low-end hardware separately.** What holds on a
  flagship regularly fails elsewhere; this is the most common
  post-launch discovery with this style. On iOS Safari specifically,
  `backdrop-filter` inside a `position: fixed` element can wreck scroll
  performance — which is exactly where glass chrome wants to live, so
  measure it on device (§11.6.8).

**Token recipe (OKLCH).** Glass surface
`oklch(1 0 0 / 0.72)` over light backdrops, `oklch(0.25 0.02 250 / 0.66)`
over dark; border `oklch(1 0 0 / 0.30)` 1px; shadow
`0 8px 32px oklch(0.2 0.05 250 / 0.18)`; text always a solid, non-alpha
token.

---

#### 11.5.5 Neumorphism / Soft UI — *restricted*

**What it is.** Elements extruded from a single-tone background using
paired light and dark shadows, so control and surface are the same
material. Looks superb in a static mockup.

**Status on our projects: restricted.** It is a known accessibility
hazard — its defining move (removing the contrast boundary between a
control and its background) is a direct violation of §12.2 Perceivable and
§11.1 heuristic #6. It fails harder than glassmorphism because the contrast
loss is structural, not incidental.

**Permitted only in the "new neumorphism" form:** applied at *component*
level to a few tactile controls (toggles, sliders, dials, a play button),
inside an otherwise flat interface, with:
- a real border or a ≥3:1 luminance boundary on every interactive element,
  so the control is perceivable without relying on the shadow pair;
- text and icons on the control meeting 4.5:1 against the surface, which
  in practice means the label is a much darker or lighter token than the
  soft-UI background;
- a focus ring that is a solid outline, not a shadow variant;
- press/active states carried by both the shadow inversion *and* a
  non-shadow change (color, label, icon).

**Never use it for:** primary buttons, form fields, anything read at speed,
anything a first-time user must find. If you're reaching for it to make a
CTA look nice, use §11.5.1 with a proper accent instead.

**Token recipe (OKLCH).** Single background hue at
`oklch(0.94 0.01 265)`; raised = light shadow `oklch(1 0 0 / 0.85)`
top-left plus dark shadow `oklch(0.70 0.02 265 / 0.55)` bottom-right;
inset for pressed. Keep the shadow *pair* symmetric — asymmetry is what
makes it read as fake.

---

#### 11.5.6 Claymorphism

**What it is.** Neumorphism's chunkier cousin: puffy, heavily rounded
(24px+), pastel or vivid soft shapes with an inner glow and a large soft
outer shadow, sitting on a colored background rather than a matched one.
Toy-like and friendly.

**Use it when:** consumer products aimed at a casual or younger audience —
kids' apps, learning tools, wellness, playful onboarding, marketing pages.
Poor fit for anything that needs to read as serious, financial, or
technical.

**Constrained form.** Because clay elements sit on a *contrasting*
background rather than a matched one, it avoids neumorphism's core defect —
but the pastel palettes it invites don't survive contrast checks. Enforce:
text at 4.5:1 against the clay fill (which usually means dark text on light
clay, not white on pastel), and shape boundaries at ≥3:1 against the page.
Chroma is the lever to pull here — in OKLCH you can hold the pleasant hue
and drop lightness until contrast passes, which is exactly the tuning HSL
makes painful.

**Token recipe (OKLCH).** Page `oklch(0.95 0.03 300)`; clay surface
`oklch(0.88 0.09 300)`; inner highlight `inset 0 4px 12px
oklch(1 0 0 / 0.55)`; outer `0 12px 24px oklch(0.60 0.10 300 / 0.35)`;
radius 24–32px; text `oklch(0.28 0.06 300)`.

---

#### 11.5.7 Neubrutalism / Brutalism

**What it is.** Raw, anti-polish: thick solid black borders, hard offset
shadows with no blur, vivid saturated accents on warm off-white surfaces,
oversized type, deliberately blunt layout. Brutalism proper goes further —
default-ish typography, exposed structure, jarring composition, minimal
ornament.

**Use it when:** portfolios, developer-brand sites, zines, editorial,
campaign microsites, products whose entire positioning is "not another
SaaS template." A genuinely good fit when standing out *is* the goal.

**Constrained form — the surprise here is that it's usually our most
accessible expressive theme.** Its native high contrast and hard borders
satisfy §12.2 almost by accident. What it still owes:
- **Focus states must be distinguishable from the resting border.** When
  every element already has a 3px black border, the default focus ring
  disappears — use a differently-colored or offset ring
  (`outline-offset`).
- **Deliberate ≠ confusing.** Nielsen #4 (§11.1) still applies: a button
  may look raw, but it must still be identifiable as a button, and
  navigation must stay consistent across pages.
- **Don't let "intentional roughness" excuse broken semantics.** Semantic
  HTML, keyboard operability, and reading order are unaffected by
  aesthetic (§12.2 Robust).
- **Watch text expansion (§13)** — brutalism's oversized type in tight
  boxes clips fast in longer languages.

**Token recipe (OKLCH).** Surface `oklch(0.98 0.01 95)` (warm off-white);
ink/border `oklch(0.15 0 0)` at 2–3px; primary accent
`oklch(0.85 0.18 95)` (vivid yellow) or `oklch(0.62 0.20 25)`; shadow
`4px 4px 0 oklch(0.15 0 0)` — hard, zero blur; radius 0–4px.

---

#### 11.5.8 Skeuomorphism

**What it is.** Digital elements imitating real materials — leather,
brushed metal, paper, felt, physical knobs and switches.

**Status: niche, and only where the metaphor is load-bearing.** Legitimate
in audio/DAW plugins, synth and mixer interfaces, calculators, e-readers,
and deliberate retro products, because the physical control genuinely
teaches the interaction (Nielsen #2, §11.1 — matching the real world). As
general decoration it is dead weight: it adds asset payload, breaks at
arbitrary sizes, and typically bakes text into images, which violates §13.

**If used:** keep the metaphor consistent and complete (a knob must turn,
not just look turnable), keep all text as real text, and provide a
non-textured high-contrast mode.

---

#### 11.5.9 Bento Grid — *a layout pattern, not a skin*

**What it is.** A modular grid of varying-size cards, each holding one
self-contained content type. Filed here because teams treat it as a theme;
it composes with any of the visual styles above.

**Use it when:** dashboards, feature-overview pages, portfolios, product
landing pages, any surface with genuinely heterogeneous content types.

**Constrained form.** Gestalt common region (§11.3) is exactly why it
works — each cell is an enclosed group. Rules: one idea per cell; the most
important cell gets the largest area *and* a Von Restorff emphasis (§11.2),
not just more space; DOM order must match visual reading order for
keyboard and screen-reader users, so avoid grid placements that reorder
content visually without reordering it semantically; and define the
single-column mobile reflow order explicitly — it is a content decision,
not a CSS side effect (§11.6.6).

---

#### 11.5.10 Dark Mode — *a mode, not a theme*

**What it is.** Not a style; a second value set for the same tokens. Every
theme above needs one.

**Constrained form.**
- **Never pure black background with pure white text** — the contrast is
  fatiguing and causes halation. Use `oklch(0.18 0.01 <hue>)` surfaces and
  `oklch(0.92 0.01 <hue>)` text.
- **Elevation inverts:** in light mode raised surfaces get shadows; in
  dark mode raised surfaces get *lighter*. This is a lightness-step
  operation, which is the OKLCH argument in §11.4 in one line.
- **Desaturate accents slightly** — a chroma that reads as vivid on white
  reads as glaring on near-black. Drop C by ~0.02–0.04 and raise L.
- **Re-check every contrast pair.** Dark mode is a separate audit, not an
  inherited pass.
- Drive it from `prefers-color-scheme` with a manual override the user can
  set, and persist that choice.

---

#### 11.5.11 Aurora / gradient-mesh, Holographic, Retro-Y2K/CRT, Maximalism, Spatial 3D

Grouped because they share one constraint: **they are decorative
backdrops or brand moments, and they must never be the substrate that
functional content sits directly on.**

- **Aurora / gradient mesh** — soft shifting multi-hue gradients. Fine for
  hero sections and empty states. Text over it needs a solid or
  semi-opaque plate. Animate slowly or not at all, and stop entirely under
  `prefers-reduced-motion`.
- **Holographic / iridescent** — hue-shifting surfaces. Very high visual
  cost, exhausting outside short brand moments; effectively impossible to
  keep contrast-stable, so keep it off anything readable.
- **Retro / Y2K / terminal-CRT** — scanlines, dithering, bitmap type,
  phosphor glow. Charming for developer tools and games; scanline overlays
  and flicker are a real accessibility risk (motion sensitivity, low
  vision) and must be toggleable and off by default under
  `prefers-reduced-motion`. Keep monospace type at ≥14px.
- **Maximalism** — dense pattern, clashing color, layered type. Directly
  opposed to Nielsen #8 and Hick's Law (§11.1, §11.2). Acceptable on a
  landing page, unacceptable in an application. If used, keep one calm
  region per screen where the actual action lives.
- **Spatial / 3D UI (AR/VR, Vision-Pro-style)** — a genuinely different
  interaction model, not a skin; if a project targets it, its platform
  HIG supersedes this section for the spatial surfaces, and §11.5.0
  still applies to the flat panels inside it.

---

#### 11.5.12 Choosing one

Default to **§11.5.1 Flat/Minimalism** unless a specific reason overrides
it. Then:

| If the product is… | Start from |
| --- | --- |
| Internal tool, admin, dashboard, data-dense | Flat / Minimalism, optionally Bento layout |
| Content- or reading-led (docs, editorial, marketing) | Swiss / Typographic |
| Android-first or cross-platform, team wants a full system | Material 3 |
| Consumer app, iOS/macOS-targeted, overlay-heavy | Flat base + Glassmorphism on chrome |
| Playful, casual, younger audience | Claymorphism |
| Brand-forward, portfolio, must not look generic | Neubrutalism |
| Audio/instrument/physical-control metaphor | Selective Skeuomorphism |
| Anything at all | …plus a Dark Mode token set |

**Combine at most two**, and give them separate jobs: one is the base
(carrying all content), the second is an accent used on a specific layer
(chrome, or a few tactile controls). "Flat base + glass overlays" and
"flat base + selective neumorphic controls" are the two combinations that
reliably work. Three stacked styles is not a theme, it's an unmaintained
token file.


### 11.6 Mobile-First & Responsive Engineering

*(Applies to any project with a web or mobile user-facing interface.)*
Mobile-first is not "make it work on a phone too." It is a **content
strategy enforced by a constraint**: design the most constrained viewport
first, decide what genuinely matters there, then layer on complexity as
space allows. The discipline is the point — a page that's well-organized at
360px is almost always well-organized at 1440px, and the reverse is rarely
true.

Practically, this means base CSS targets the smallest supported viewport
and `min-width` media queries add capability upward. Writing it in that
direction produces cleaner CSS (you add as space appears, rather than
unwinding as space disappears) and it makes the mobile experience the
default rather than the leftover.

**When this section doesn't apply:** genuinely desktop-only software —
IDEs, video editors, complex CAD-like tools, some internal ops consoles.
Say so explicitly in the project README and set a minimum supported width;
don't ship a half-broken mobile layout and call it responsive. If the
product is *reachable* on a phone, though, at minimum it must be readable
and navigable there.

#### 11.6.1 Content priority before layout

Before any breakpoint is written, classify each screen's content:

- **Must show** — the essential content and the primary action, visible
  without scrolling on a 360×640 viewport.
- **Should show** — supporting content, reachable with a scroll.
- **Can show** — enhancements that appear only when there's room.

If everything is "must show," the prioritization hasn't been done yet.
This directly serves Hick's Law and Nielsen #8 (§11.1, §11.2): the phone
forces the triage that a wide screen lets you avoid.

Corollary: **mobile gets the same capability, not a subset.** Hiding a
feature behind `display: none` at small widths is how a "responsive" site
becomes a degraded one — and it maps onto the equity failure named in
§12.1.1.

#### 11.6.2 Breakpoints, viewport, and container queries

- **Breakpoints go where the content breaks, not where a device is.**
  Widen the window slowly; where line lengths get too long, cards get too
  wide, or whitespace goes slack, that's a breakpoint. Tuning to exactly
  375px and 768px because two popular phones sit there breaks the moment
  someone uses a foldable, split-screen multitasking, or a half-width
  desktop window.
- **Three to five breakpoints covers almost everything.** A reasonable
  baseline, to be adjusted per project: mobile (base, no query), ~640px,
  ~768px, ~1024px, ~1280px, and a ~1536px step only if the design genuinely
  needs a distinct treatment there. More than five is maintenance cost
  without benefit.
- **One source of truth for breakpoints** — a token set shared by the CSS,
  the framework config (Tailwind/Bootstrap), and the design file. Drift
  between design and code is the most common cause of responsive
  regressions.
- **Prefer container queries for components, media queries for page
  layout.** A card that responds to its own container width is reusable
  anywhere; a card that responds to viewport width is coupled to where it
  happens to be placed. Container queries are production-safe across
  modern browsers.
- **The viewport meta tag is mandatory** on every page:
  `<meta name="viewport" content="width=device-width, initial-scale=1">`.
  **Never** add `user-scalable=no` or `maximum-scale=1` — disabling pinch
  zoom is a direct §12.2 Perceivable violation for low-vision users.
- **Design to 320px as the floor**, even if you optimize around 360–390px.
  WCAG reflow requires content to work at a 320px-equivalent width without
  two-dimensional scrolling.

#### 11.6.3 Fluid space and type

- **Fluid over stepped.** Use `clamp(min, preferred, max)` for type and
  major spacing so a single rule scales smoothly from 360px to 1920px
  instead of jumping at breakpoint cliffs — e.g.
  `font-size: clamp(1.75rem, 4vw + 0.5rem, 3.5rem)`. Always set both a
  floor and a ceiling; unbounded `vw` sizing is unreadable at the extremes.
- **`rem` for type and spacing, not `px`**, so the layout respects the
  user's browser font-size setting. Fixed-`px` type silently ignores an
  accessibility preference a user has already expressed.
- **Body text ≥16px, and form inputs ≥16px specifically** — iOS Safari
  auto-zooms into any input with a computed font-size below 16px, which
  yanks the layout sideways mid-form. This is the single most common
  self-inflicted mobile form bug.
- **The 8-point spacing scale (§11.4) still governs**, expressed as tokens
  (4/8/12/16/24/32/48/64). Fluid sizing changes the *values*, not the
  rhythm.
- **Line length 45–75 characters** at every breakpoint. On mobile this
  usually means edge padding of 16–24px, not zero.

#### 11.6.4 Viewport units and safe areas

`100vh` is measured against the *large* viewport (browser chrome
retracted), so on mobile a `100vh` element is taller than what the user can
actually see on load — the classic "my CTA is hidden behind the address
bar" bug. It affects Chrome, Firefox, and Samsung Internet, not just
Safari. Use the dynamic viewport units:

- **`svh` is the default choice** — the small viewport, worst case with
  all browser UI visible. Correct for hero sections and anything that must
  be fully in frame on first load.
- **`lvh`** — the large viewport. Correct for full-screen modals and
  overlays, which should cover everything.
- **`dvh`** — tracks the currently visible height, recalculating as chrome
  shows and hides. Correct for app-shell layouts (fixed header, scrolling
  body, bottom nav), but it triggers layout recalculation on every toolbar
  change, so it causes visible jank on complex trees. Don't reach for it by
  default.
- **Don't mix unit families within one component** — combining `vh` and
  `dvh` in the same layout produces jarring shifts as chrome state changes.
- **Respect safe-area insets on edge-to-edge displays**:
  `padding-bottom: env(safe-area-inset-bottom)` and its siblings, so
  content and — critically — bottom-anchored actions don't sit under the
  home indicator, notch, or camera housing.
- **The virtual keyboard doesn't move these units.** It shrinks the visual
  viewport, not the layout viewport. Handle keyboard-induced layout
  explicitly rather than assuming `dvh` accounts for it.

#### 11.6.5 Touch ergonomics — targets, spacing, and reach

**Target size — the standard on our projects:**

| Level | Size | Status |
| --- | --- | --- |
| WCAG 2.5.8 (AA) | 24×24 CSS px | Absolute legal/compliance floor |
| Our working minimum | 44×44 CSS px | Required for any touch target |
| Preferred | 48×48 CSS px | Matches Material; use for primary actions |
| Primary CTA / high-stakes | 56–64px height | Fitts's Law applied (§11.2) |

The visual element may be smaller than the target — a 24px icon inside a
44px hit area is correct and normal. Extend the hit area with padding, not
by scaling the icon up.

**Spacing matters more than size above ~40px.** Target *separation* has a
larger effect on tap error rate than target size once targets are
reasonably large; WCAG 2.5.8 codifies this by letting a 24px target pass
when it has adequate spacing. Our defaults: **16px between targets in
dense lists and near screen edges, 12px in general use, 8px only between
large (≥44px) targets.** Never place a destructive action adjacent to a
common one at tight spacing.

**Reach — the thumb zone, held loosely.** Hoober's field observations of
~1,300 people found roughly 49% one-handed, 36% cradled, 15% two-handed,
with about 75% of interactions thumb-driven and about two-thirds of
one-handed grips right-thumbed. What follows from that:

- **The comfortable zone is a curved arc across the lower-center of the
  screen**, not a rectangle, and it does not grow when the phone does —
  larger phones mean proportionally *more* unreachable area.
- **Top corners are the worst place for anything you want tapped.** This
  inverts the desktop habit of parking the primary action top-right.
  Primary actions, next/submit buttons, and main navigation belong at the
  bottom.
- **Destructive and irreversible actions go deliberately outside the easy
  zone**, or behind a confirmation — accidental taps concentrate exactly
  where the thumb rests (§12.1.5, tolerance for error).
- **Design for both handedness and grip variety.** Users switch grips
  constantly, and left-thumb use is far more common than left-handedness
  in the population. Don't build a layout that only works right-handed;
  evaluate a combined left/right overlay.
- **The thumb zone is a model, not a template.** Validate against real
  tap data where you have it.

**Input modality rules:**

- **Nothing may depend on hover.** Hover has no touch equivalent. Every
  hover affordance needs a tap/focus equivalent, and tooltips carrying
  necessary information are a mobile failure by construction.
- **Every gesture needs a visible alternative.** Swipe-to-delete,
  long-press menus, and pinch actions are accelerators (§11.1 heuristic 7),
  never the only path — they're undiscoverable and unusable via assistive
  tech.
- **Don't hijack native gestures** — browser back-swipe, pull-to-refresh,
  and edge swipes belong to the OS. Custom horizontal scrollers near screen
  edges routinely fight the back gesture.
- **Give touch feedback within ~100ms** — active/pressed states, not just
  hover states, or the tap feels dropped (§11.2, Doherty Threshold).

#### 11.6.6 Mobile layout and navigation patterns

- **Put primary navigation at the bottom** on mobile (tab bar or bottom
  action bar), not behind a top-corner hamburger. A hamburger hides
  information architecture behind an extra tap in the hardest-to-reach
  corner — use it for secondary/overflow items, not for the main paths.
- **Budget vertical space deliberately.** Sticky headers, cookie banners,
  and promo bars each eat scarce viewport height; a sticky header should be
  compact or collapse on scroll.
- **Tables don't survive on mobile.** Convert to stacked cards, a
  key-value list, or a horizontally scrolling region with a frozen first
  column and a visible scroll affordance — never a table that silently
  overflows.
- **Prefer bottom sheets to centered modals** on mobile: they land in the
  reachable zone and match platform convention (§11.2, Jakob's Law).
  Whatever the pattern, dismissal must be possible without a precise tap on
  a small top-corner ✕.
- **Reflow order is a content decision.** When a multi-column layout
  collapses to one column, the resulting order must match importance — and
  DOM order must match visual order, or keyboard and screen-reader users
  get a different sequence than sighted ones (§11.5.9, §12.2 Operable).
- **Fixed bottom bars must account for safe-area insets** (§11.6.4) and
  must not cover the last item of a scrolling list — pad the scroll
  container by the bar's height.

#### 11.6.7 Forms on mobile

Forms are where mobile UX is won or lost, because typing on a phone is
expensive.

- **Single column, always.** Multi-column form layouts break reflow and
  confuse tab order.
- **Labels above fields, always visible.** Placeholder-as-label
  disappears the moment typing starts, which is a §11.1 heuristic 6
  (recognition over recall) failure and an accessibility one.
- **Summon the right keyboard.** Use the correct `type` plus `inputmode`
  (`numeric`, `decimal`, `tel`, `email`, `url`, `search`) and
  `enterkeyhint`. A numeric keypad for an OTP field is a two-character
  change that measurably reduces abandonment.
- **Use `autocomplete` tokens** (`given-name`, `email`, `one-time-code`,
  `postal-code`, `cc-number`) so the platform can autofill. This is
  Tesler's Law in practice (§11.2) — the system absorbing work instead of
  the user.
- **Minimize typing.** Prefer selection, sensible defaults, device
  capabilities (camera, location, contacts, OTP autofill) over free text.
- **Validate inline and forgivingly** — accept spaces in card numbers and
  phone numbers, trim whitespace, be liberal in what you accept (Postel's
  Law, §11.2). Show errors next to the field, not only in a summary at the
  top that's scrolled off screen.
- **The submit button must be reachable with the keyboard open** — either
  in flow beneath the last field or in a keyboard-aware sticky footer.
  Verify with the keyboard actually open, not just in DevTools.
- **Never disable zoom to "fix" input zoom** (see §11.6.2) — set the input
  font-size to 16px instead.

#### 11.6.8 Mobile performance budget

Performance is a feature on mobile, and it is measured on the devices
users actually have — not on the machine the code was written on.

**Core Web Vitals thresholds** (field data, 75th percentile):

| Metric | Good | Measures |
| --- | --- | --- |
| LCP | ≤ 2.5s | Loading — when main content appears |
| INP | ≤ 200ms | Responsiveness across all interactions |
| CLS | ≤ 0.1 | Visual stability |

**Starting byte budget for an initial mobile load** (tune per project,
but write it down and enforce it in CI): HTML < 50KB, CSS < 60KB, JS
< 150KB gzipped, above-the-fold images < 200KB, fonts < 80KB — roughly
**< 550KB total initial load**.

- **Images are the biggest single lever.** Serve AVIF with a WebP
  fallback; use `srcset`/`sizes` so a 360px screen never downloads a
  1600px asset; set explicit `width`/`height` (or `aspect-ratio`) to
  reserve space and prevent CLS; `loading="lazy"` below the fold and
  `fetchpriority="high"` on the LCP image.
- **INP is usually the hardest metric to pass.** Break up long tasks
  (>50ms), move computation off the main thread, and prefer CSS to
  JavaScript for anything CSS can do — transitions, sticky positioning,
  scroll snapping, `:has()` state.
- **Third-party scripts are the usual culprit** when a content site fails
  CWV. Every added tag is a budget decision, per §10.
- **Fonts:** subset, `font-display: swap`, preload only what the
  first paint needs, and cap the number of families/weights (§11.4 already
  limits you to two weights).
- **Theme effects count against the budget** (§11.5.0 rule 7) —
  `backdrop-filter`, large shadow stacks, and animated gradients are GPU
  work on a phone. On iOS Safari specifically, `backdrop-filter` inside a
  `position: fixed` element is a known scroll-performance hazard.
- **Test on a real mid-range Android device and on throttled 3G/4G**, and
  treat field data (CrUX/RUM) as the source of truth — a green Lighthouse
  score on a developer laptop says nothing about the 75th percentile of
  real users.

#### 11.6.9 The mobile verification checklist

Nothing ships as "responsive" until it's been checked at:

1. **320px** — the reflow floor: no horizontal scrolling, nothing clipped.
2. **360–390px** — the realistic mobile target where it should feel good,
   not merely function.
3. **768px and ~1024px** — tablet portrait and landscape, including the
   awkward in-between widths, not just the exact breakpoints.
4. **Landscape orientation on a phone** — short viewport height, where
   sticky headers plus a keyboard leave almost nothing.
5. **With the virtual keyboard open**, on a real device — the most
   commonly skipped check and the most commonly broken state.
6. **On a real mid-range Android phone**, not only a simulator: DevTools
   does not accurately reproduce browser-chrome behavior, touch accuracy,
   or GPU limits.
7. **At 200% browser zoom / large system font**, since layouts built in
   `px` collapse here.
8. **With `prefers-reduced-motion`, `prefers-reduced-transparency`, and
   dark mode active** (§11.5.0 rule 6).
9. **Split-screen or foldable widths** where the target audience uses them
   — arbitrary widths that match no device spec.
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
   fatigue: adequately large touch targets (Fitts's Law, §11.2; concrete
   sizes in §11.6.5), minimal required precision, sensible defaults that
   reduce repetitive input.
7. **Size and space for approach and use** — usable regardless of the
   user's body size, posture, or mobility — or, for digital products,
   regardless of their device, screen size, input method, or assistive
   hardware. In practice this is what §11.6 operationalizes: reach, grip,
   viewport range, and input modality are all part of this principle, not
   separate concerns.

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
  should follow visual/logical order. Two criteria that bite hardest on
  touch devices: **Target Size (Minimum), SC 2.5.8 (AA)** — 24×24 CSS px,
  or smaller with adequate spacing; and **Reflow, SC 1.4.10 (AA)** —
  content must work at a 320px-equivalent width without two-dimensional
  scrolling. Our working standard exceeds the target-size floor; see
  §11.6.5.
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
images, labeled form fields, sufficient color contrast, full keyboard
operability, touch targets at the §11.6.5 working minimum, pinch zoom never
disabled, and usable reflow at 320px. Treat WCAG AA conformance as the
working default, not an eventual nice-to-have.

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
  English. This compounds with mobile — a label that fits at 360px in
  English may not in German, so run the pseudo-localization check at the
  narrow end of the breakpoint range (§11.6.9), not just at desktop width.
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
- **Record architectural decisions, including the options you rejected.**
  A short ADR (context, decision, alternatives considered, consequences)
  for anything that meets the §2.5 "get approval before major changes"
  bar. It stops the next person re-litigating a settled question or
  "fixing" something deliberate. Doc *types* matter too — tutorial,
  how-to, reference, and explanation answer different questions and don't
  substitute for each other (§18.1).

## 16. Definition of Done

A feature or change isn't done until:

1. It works end-to-end (backend and frontend, where both apply) — not just
   the happy path.
2. Errors are handled explicitly and surfaced clearly, per §8.
3. Any new configurable value lives in config/settings, not hardcoded, per
   §7.
4. Any new or changed API endpoint meets the contract in §4.7 — accurate
   status codes, RFC 9457 errors, pagination, idempotency on unsafe
   operations, and an updated spec.
5. Any user-facing surface meets the working accessibility minimum, per
   §12.2 — including under the project's chosen visual theme, per the theme
   contract in §11.5.0.
6. Any user-facing surface has been verified against the mobile checklist
   in §11.6.9 and stays within the project's performance budget, per
   §11.6.8.
7. Relevant docs (README, user guide, API docs) are updated to reflect it,
   per §15.
8. The change is committed in small, reviewable increments with clear
   messages, per §15.

If a change doesn't meet all eight, it's not finished — it's in progress.

## 17. Useful Commands (adapt per project)

```bash
# Python
black . && ruff check . --fix && flake8 .
pytest

# JS/TS
prettier --write . && eslint . --fix
npm test

# Mobile / performance audit (§11.6.8) — run against a deployed URL,
# and treat field data (CrUX/RUM) as the real source of truth.
npx lighthouse <url> --preset=desktop
npx lighthouse <url> --form-factor=mobile --throttling-method=simulate
npx @unlighthouse/cli --site <url>   # whole-site sweep
```


## 18. Craft: Software Developers Love and Users Return To

Everything above this section keeps software from being *bad*. This
section is about what makes it *good* — the difference between a codebase
people tolerate and one they're glad to open, and between a product people
use once and one they come back to because it earns the return.

Two loyalties, and they are not in tension: **the developer inherits the
codebase, and the user inherits the product.** Most of what follows is
about respecting whichever of them shows up after you've left.

### 18.1 What developers actually love

Not cleverness. The things engineers consistently rate highest are
unglamorous: fast feedback, low friction, and being trusted with a system
they can understand.

- **Clone to running in one command, in under ten minutes.** This is §9's
  zero-touch setup, and it is the single strongest signal of how a project
  will treat you. Every manual step in a README is a tax paid by every
  contributor forever — including future-you at 2am.
- **Fast feedback beats almost every other improvement.** A test suite that
  runs in 30 seconds gets run; one that takes 20 minutes gets skipped, and
  then the CI queue becomes the feedback loop. Optimize the inner loop
  (save → see result) before optimizing anything else about the workflow.
- **Flaky tests are worse than missing tests.** A test that fails randomly
  teaches the team to ignore failures — which is the exact capability you
  needed the suite for. Fix or delete; never re-run and move on.
- **Errors should name the fix, not just the failure.** "Config validation
  failed: `DATABASE_URL` is not set. Add it to `.env` — see
  `.env.example`." A framework or library that tells you what to do next
  is the one people recommend to their friends.
- **Make the right thing the easy thing.** If the correct pattern requires
  discipline and the wrong one is a one-liner, the wrong one wins at
  scale. Encode conventions in linters, types, templates, and generators
  rather than in review comments and tribal memory.
- **Boring is a feature.** A predictable codebase using well-understood
  tools lets people spend their attention on the problem. Novel
  abstractions spend that attention on the code itself. Reserve your
  innovation budget for the part of the system that is genuinely your
  product.
- **Documentation that answers the reader's actual question.** Four
  distinct kinds, and they don't substitute for each other: a *tutorial*
  (get me to my first success), a *how-to* (do this specific task), a
  *reference* (what are the parameters), and an *explanation* (why is it
  built this way). Most projects write only reference docs and wonder why
  onboarding is slow.
- **Write down the *why*, especially for rejected options.** A short
  architecture decision record — context, decision, alternatives
  considered, consequences — saves the next person from re-litigating a
  question you already answered, or worse, from "fixing" something
  deliberate. This is §3's "comment intent, not mechanics" at
  architecture scale.
- **Leave the campsite cleaner.** Small, continuous improvement in the code
  you happen to be touching beats a scheduled refactor that never gets
  scheduled.
- **Measure the experience, don't assume it.** Time-to-first-contribution,
  cycle time from commit to production, build/test duration, and how often
  people have to context-switch to get unblocked. If onboarding takes two
  weeks, that is a bug in the project, not a fact about new hires.

### 18.2 Reliability is the feature users notice most

Users don't experience your architecture; they experience whether the
thing worked. Ranked by how much goodwill each earns per unit of effort:

1. **It doesn't lose their data.** Everything else is negotiable. Backups
   that have been *restored from* at least once, transactions with real
   boundaries (§4.4), and no destructive operation without a confirmation
   or an undo.
2. **It's fast enough to feel immediate** — the Doherty Threshold (§11.2)
   and the mobile budget (§11.6.8). Perceived speed counts: optimistic
   updates, skeletons, and doing the work in the background beat a
   spinner over a fast backend.
3. **It behaves the same way every time.** Consistency is what allows a
   person to build a mental model, and a mental model is what turns
   effortful use into fluent use.
4. **It fails honestly.** State what happened, what it means for their
   data, and what to do next (§8). Users forgive errors; they don't
   forgive being lied to by a green checkmark.

### 18.3 Earning the return visit — honestly

The brief here is software people *want* to come back to. There is a
well-documented playbook for manufacturing compulsion, and this document
already refuses it (§11.2, ethical note). The distinction is simple and
worth stating as a test:

> **The test:** would the user endorse this mechanism if you explained it
> to them in full? Genuine value survives the explanation — "we send you
> a digest because you asked for one." Manufactured compulsion doesn't —
> "we withhold the notification count until you open the app."
> If a mechanism only works *because* the user doesn't see it, don't
> ship it.

What builds a real habit:

- **Time to first value, ruthlessly short.** People decide whether
  something is for them in the first session. Get them to one real,
  personally meaningful outcome before asking for a signup, a
  configuration, or a tour. Defaults that work beat a settings page.
- **Reduce the work rather than reward the visit.** The durable hook is
  that the product genuinely does something tedious for them (Tesler's
  Law, §11.2). Streaks and badges layered on top of a product that saves
  nobody any time are decoration on a leak.
- **Invest in the peak and the ending** (Peak-End Rule, §11.2). The moment
  something succeeds and the moment a flow completes are what people
  remember and describe to others. A confirmation screen that's clear,
  fast, and slightly generous is worth more than three optimized middle
  steps.
- **Let the product get better as they use it** — accumulated data, saved
  preferences, learned patterns. This is switching cost created by
  *earned* value, not by a data export you made deliberately painful.
- **Notify on a budget you'd defend out loud.** Every notification spends
  trust. Default to fewer, make them genuinely actionable, make
  granular controls easy to find, and make unsubscribing one click.
  A product that respects attention gets opened; one that demands it gets
  muted, and muted is one step from deleted.
- **Make leaving easy.** Full data export, clear cancellation, no
  retention maze. Counterintuitively this increases trust and adoption —
  and it's the concrete form of §11.1 heuristic 3 (user control and
  freedom).
- **Close the loop with the people who report things.** Users who get a
  reply and then see their bug fixed become the ones who defend the
  product to other people. This is the cheapest advocacy that exists and
  almost nobody does it.

### 18.4 Small things with outsized returns

- **Empty states are a design surface, not a blank screen.** A first-run
  empty state is the best teaching moment the product will ever get: show
  what goes here and give one button to create it.
- **Keyboard support for anything used daily.** Power users are the ones
  who evangelize; shortcuts are how a tool goes from usable to loved
  (§11.1 heuristic 7).
- **Copy is interface.** A precise button label prevents more errors than
  a validation rule catches (§11.4). Write the microcopy before the
  polish, not after.
- **Make the common case one step and the rare case possible.** Not the
  reverse, and not both at equal prominence.
- **Preserve work relentlessly** — drafts, form state on navigation, undo
  for destructive actions. Losing someone's typing is a small betrayal
  they remember for a long time.
- **Ship small and often**, and say what changed in language a user
  recognizes. A visible, honest changelog is a trust-building device.
- **Sweat the last 10%.** Loading states, focus order, error copy, the
  offline case, the very-long-name case, the zero-items and
  ten-thousand-items cases. Users can't articulate why one product feels
  solid and another doesn't — this is almost always the difference, and
  it's also the Aesthetic-Usability Effect (§11.2) working for you rather
  than against you.

### 18.5 What to do when this section conflicts with a deadline

It will. The honest ordering, when something has to give:

1. Don't lose data, don't ship a security hole (§7).
2. Fail visibly rather than silently (§8) — a known gap beats an unknown
   one.
3. Cut scope, not quality, on what ships. A smaller thing done properly
   beats a larger thing done partially, and it's much cheaper to extend
   than to repair.
4. Write down what you cut and why, in the same commit or an issue.
   Undocumented shortcuts are the ones that become permanent.
---

## References

The principles in §4 and §11–§13 are drawn from published research,
established standards, and platform specifications — not house opinion.
For further reading:

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
- Ottosson, B. (2020). *OKLab: A perceptual color space for image
  processing*; W3C — *CSS Color Module Level 4* (`oklch()`).
- Nielsen Norman Group — *Glassmorphism: Definition and Best Practices*;
  Apple Human Interface Guidelines (Materials / Liquid Glass); Google —
  *Material Design 3*. Used for §11.5, alongside the accessibility
  constraints in §12.2, which take precedence over any of them where they
  conflict.
- Hoober, S. (2013). *How Do Users Really Hold Mobile Devices?* UXmatters —
  the grip and reach field study underlying §11.6.5; Clark, J. —
  *Designing for Touch.*
- W3C — *WCAG 2.2* SC 2.5.8 Target Size (Minimum, AA), SC 2.5.5 Target Size
  (Enhanced, AAA), SC 1.4.10 Reflow; Apple HIG (44pt) and Material Design
  (48dp) touch-target guidance.
- W3C — *CSS Values and Units Level 4* (small/large/dynamic viewport units:
  `svh`, `lvh`, `dvh`); *CSS Containment Level 3* (container queries).
- Google web.dev — *Core Web Vitals* (LCP, INP, CLS thresholds and field
  measurement at the 75th percentile), used for §11.6.8.
- Cockburn, A. — *Hexagonal Architecture (Ports and Adapters)*; Evans, E.
  (2003) — *Domain-Driven Design*; Fowler, M. — *Patterns of Enterprise
  Application Architecture* and *Strangler Fig Application*; Richardson,
  C. — *Microservices Patterns* (Saga, Transactional Outbox, CQRS);
  Nygard, M. (2007/2018) — *Release It!* (Circuit Breaker, Bulkhead,
  timeouts, backpressure). Basis for §4.3–§4.6.
- IETF — *RFC 9457, Problem Details for HTTP APIs* (superseding RFC 7807);
  public API engineering references from Stripe (idempotency keys),
  GitHub, and Google. Basis for §4.7.
- Procida, D. — *Diátaxis* (tutorial / how-to / reference / explanation),
  and Nygard's *architecture decision records*, referenced in §15 and
  §18.1.

*This document sets the standard for how code is written on projects that
reference it. Project-specific requirements (product scope, data models,
timelines) belong in that project's own PRD/README — this file stays
project-agnostic so it can be reused as-is elsewhere.*
