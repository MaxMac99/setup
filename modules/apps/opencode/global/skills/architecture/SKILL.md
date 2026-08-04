---
name: architecture
description: Use when designing a feature, deciding where code belongs, reviewing structural changes, or writing the design section of an epic or ticket. Covers domain-driven design, layering, coupling, deployment fit, and when a mermaid diagram is worth drawing.
---

# Architecture

## Domain first

Before deciding where code goes, decide what it *is*.

- **Bounded context** — the area within which a term has one meaning. If
  "Account" means two different things in two places, that is two contexts, and
  forcing one model on both produces the mess that never stops costing.
- **Ubiquitous language** — the names in the code match the names the domain
  uses. If the ticket says "sync" and the code says `refresh`, one of them is
  wrong. Fix it during refinement, not later.
- **Aggregate** — the unit that must stay consistent as a whole. Its boundary
  is a transaction boundary. Aggregates reference each other by identity, not
  by holding each other's objects.
- **Invariant** — something that must always be true. Enforce it inside the
  aggregate that owns it. An invariant enforced in three call sites is an
  invariant that will be violated by the fourth.

When a change spans contexts, say so explicitly and name the relationship:
shared kernel, customer/supplier, anticorruption layer. Cross-context coupling
that nobody named is how a modular system becomes a distributed monolith.

## Where logic belongs

| Layer | Holds | Must not |
| --- | --- | --- |
| Domain | entities, value objects, invariants, domain services | know about HTTP, SQL, files, clocks, or config |
| Application | use cases, orchestration, transaction boundaries | contain business rules |
| Infrastructure | persistence, clients, serialisation, framework glue | make decisions |

Dependencies point inward. Infrastructure depends on domain, never the reverse.
The practical test: if you cannot unit-test the rule without a database or a
network, the rule is in the wrong layer.

Two smells worth naming when you see them:

- **Anemic domain** — structs with public fields and all behaviour in
  "services". The invariants have nowhere to live, so nothing enforces them.
- **Leaked persistence** — ORM annotations, column names or nullability driving
  the shape of a domain type. The database schema is an implementation detail
  of a repository, not the model.

## Deployment fit

A design is not finished until you can say how it ships. For each change, ask:

- **Migration** — does this need a schema or data migration? Is it
  backwards-compatible, so the old and new code can run simultaneously during
  the rollout? If not, that is a two-phase deploy and the ticket must say so.
- **Rollback** — if this is reverted after release, what breaks? Data written
  in the new shape and read by old code is the usual trap.
- **Config and secrets** — new configuration goes through the existing
  mechanism (nix modules, sops), never a literal in code. New secrets need a
  sops entry and a rotation story.
- **Failure** — what happens when the dependency this calls is down? Timeout,
  retry, and fallback are design decisions, not implementation details, and
  they belong in the acceptance criteria.
- **Observability** — how will you know it works in production, and how will
  you debug it when it does not?

## Diagrams

Diagrams render in three places: inline in neovim (snacks.image via `mmdc`),
natively on GitHub in issues and pull requests, and in the opencode TUI via
`/diagram`. Use mermaid — it is the only format that works in all three.

Draw one when the structure is genuinely hard to hold in your head:

| Situation | Diagram |
| --- | --- |
| new component and its neighbours | `flowchart` or `C4Context` |
| a flow crossing several services or processes | `sequenceDiagram` |
| new or changed persisted data | `erDiagram` |
| a lifecycle with non-obvious transitions | `stateDiagram-v2` |
| model relationships within a context | `classDiagram` |

**Do not draw a diagram that restates the prose.** Three boxes in a row saying
"API → Service → Database" is noise. A diagram earns its place when it shows
something the text cannot say concisely: a cycle, a fan-out, an ordering
constraint, an unexpected dependency.

Keep them small. If a diagram needs more than about a dozen nodes, it is
answering more than one question — split it, or cut it down to the part that is
actually in question.

## Judging a design

When reviewing rather than designing, work through these in order:

1. **Boundaries** — is the change in the right context, and does it respect
   existing boundaries or quietly cross one?
2. **Direction** — do dependencies point inward? Any new cycle?
3. **Coupling** — what else must change when this changes? Did the change add
   a reason for two components to change together?
4. **Cohesion** — is related behaviour together, or scattered across layers?
5. **Reversibility** — how expensive is this to undo? Public wire formats,
   persisted shapes and identifiers are the expensive ones; spend the design
   effort there and move fast on the rest.
6. **Consistency** — does it match how this codebase already solves the same
   problem? A second pattern for a solved problem is a cost, and it needs a
   reason.
