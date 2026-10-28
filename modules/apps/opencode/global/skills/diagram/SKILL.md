---
name: diagram
description: Use when deciding whether a mermaid diagram belongs in a plan, ticket, PR or doc, when choosing its type, or when the user wants to see one. Renders mermaid to PNG and shows it inline.
---

# Diagrams

Decide whether a diagram earns its place, then render it to an image and show
it in this session.

## Choosing the source

1. The user names a file — render the mermaid blocks in that file.
2. The user gives mermaid source — render it directly.
3. Neither — use the newest file in `docs/plans/` or `docs/concepts/` that
   contains mermaid, else ask which file to use.

If the chosen file contains no ```mermaid blocks, say so and stop. Do not
invent a diagram to have something to render.

## Rendering

For each mermaid block, write the source to `.work/diagrams/<name>.mmd` and
render it:

```sh
mkdir -p .work/diagrams
mmdc -i .work/diagrams/<name>.mmd -o .work/diagrams/<name>.png -b transparent
```

Name diagrams after what they show — `sync-retry-flow`, not `diagram1`. When a
file has several blocks, render each separately so they can be viewed
individually.

Then **read each generated PNG**, which returns it as an attachment so it
displays inline here.

## Reporting

For each diagram: the name, what it shows in one line, and the path. If `mmdc`
fails, show its actual error — a mermaid syntax error is usually a missing
quote or an unsupported diagram type, and the message says which.

## When a diagram earns its place

Mermaid is the one format that renders everywhere here: neovim (snacks.image
via `mmdc`), GitHub issues and pull requests, and this session. Draw one only
when it shows what prose cannot say concisely: a cycle, a fan-out, an ordering
constraint, an unexpected dependency. Three boxes in a row restate the text.

| Situation | Diagram |
| --- | --- |
| a new component and its neighbours | `flowchart` |
| a flow crossing services or processes | `sequenceDiagram` |
| new or changed persisted data | `erDiagram` |
| a lifecycle with non-obvious transitions | `stateDiagram-v2` |

Past about a dozen nodes a diagram answers more than one question; split it.

## Rules

- `.work/` is gitignored, so these are scratch artefacts. Never write rendered
  images into the repository proper.
- When rendering, do not modify the source file.
- If a diagram renders but looks wrong, say so rather than presenting it as
  correct — a diagram that misrepresents the design is worse than none.
