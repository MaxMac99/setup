---
description: Render the mermaid diagrams in a draft or file to PNG and show them inline
---

Render mermaid to an image and display it in this session.

What to render (may be empty): $ARGUMENTS

## Choosing the source

1. `$ARGUMENTS` names a file — render the mermaid blocks in that file.
2. `$ARGUMENTS` is empty — use `.work/ticket.md` if it exists, else the most
   recently modified file in `.work/epics/`, else ask which file to use.
3. `$ARGUMENTS` is mermaid source itself — render it directly.

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

## Rules

- `.work/` is gitignored, so these are scratch artefacts. Never write rendered
  images into the repository proper.
- Do not modify the source file. This command renders; it does not edit.
- If a diagram renders but looks wrong, say so rather than presenting it as
  correct — a diagram that misrepresents the design is worse than none.
