---
name: architecture
description: Use when designing a feature, deciding where code belongs, reviewing structural changes, or writing the design section of a plan, epic or ticket. States the user's architecture preferences - domain-driven design, inward-pointing layers, and how changes must ship.
---

# Architecture preferences

These are choices, not explanations. Apply them unless the codebase in front of
you already does it differently; then follow the codebase and say so.

## Domain-driven design

- Name the bounded context before placing code. One term, one meaning per
  context; a term with two meanings is two contexts.
- Code uses the domain's words. If the plan says "sync" and the code says
  `refresh`, fix one of them before implementing.
- Invariants live inside the aggregate that owns them, never at call sites.
  Aggregates reference each other by identity.
- A change across contexts names the relationship: shared kernel,
  customer/supplier, or anticorruption layer.

## Layers

| Layer | Holds | Must not |
| --- | --- | --- |
| Domain | entities, value objects, invariants | know HTTP, SQL, files, clocks or config |
| Application | use cases, orchestration, transactions | contain business rules |
| Infrastructure | persistence, clients, serialisation | make decisions |

Dependencies point inward. A rule that cannot be unit-tested without a
database or network is in the wrong layer.

Reject both: an anemic domain (public fields, all behaviour in services) and
persistence leaking into domain types (ORM annotations, column names,
nullability shaping the model).

## Shipping

- Migrations must let old and new code run side by side; otherwise the plan
  says "two-phase deploy".
- New config goes through the existing nix modules, new secrets through sops.
  Never a literal.
- Timeouts, retries and fallbacks for a dependency are design decisions and
  belong in the plan, not in implementation.
