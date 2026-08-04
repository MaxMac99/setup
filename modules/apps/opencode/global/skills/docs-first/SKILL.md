---
name: docs-first
description: Use before writing code that touches an external API, library, framework, provider or CLI whose surface may have changed - adding a dependency, configuring a tool, calling an SDK, setting a flake or provider option, or picking a schema, wire format or migration strategy. Search the authoritative docs instead of relying on memory.
---

<!--
Adapted from `read-the-damn-docs` in https://github.com/BuilderIO/skills (MIT).
Examples and version-check commands rewritten for this stack.
-->

# Check the docs before guessing

Model memory of any fast-moving API is a snapshot of an average of old
versions. It is confidently wrong in exactly the places that cost the most:
renamed options, moved modules, changed defaults, deprecated fields.

**When in doubt, look it up. A search costs seconds; a plausible-looking wrong
option costs a debugging session.**

## Triggers

Search before you write, when the task involves:

- **Adding or upgrading a dependency** — a crate, a nixpkgs input, a Helm
  chart, a Pulumi provider.
- **Configuring a tool** — nix module options, Kubernetes resource fields,
  Pulumi resource arguments, CI syntax.
- **Calling an SDK or external API** — endpoints, auth, pagination, rate
  limits, error shapes.
- **A decision that is expensive to reverse** — public wire formats, database
  schema, migration strategy, persistent identifiers, anything another system
  will depend on.
- **Anything security- or billing-adjacent** — auth flows, token scopes,
  permission models, quotas.
- **Symptoms of drift** — an option that "should" exist but is rejected, an
  import that fails, a deprecation warning, a field the API ignores.

## Where to look, by stack

| Domain | Authoritative source |
| --- | --- |
| Nix / nixpkgs | the option or package definition in nixpkgs itself; `nix flake metadata` for what an input actually resolves to |
| home-manager | the module source under `modules/`, which is the real schema regardless of what the docs say |
| Rust crates | docs.rs for the **exact version** in `Cargo.lock`, not "latest"; `cargo tree` to see what you actually have |
| Kubernetes | `kubectl api-resources` and `kubectl explain <resource>.<field>` against the live cluster — the API version in front of you beats any blog |
| Pulumi | the provider's registry API docs, matched to the provider version in the lockfile |
| opencode | `https://opencode.ai/config.json`, the published schema — it hard-fails on invalid config |
| GitHub CLI / API | `gh <command> --help` for the installed version; docs.github.com for REST and GraphQL |

## Rules

- **Match the version you actually have.** Docs for a version you are not
  running are worse than no docs, because they read as authoritative. Resolve
  the real version first: `cargo tree`, `nix flake metadata`, `kubectl version`,
  `gh --version`, or read the lockfile.
- **Prefer the source over the prose.** For nixpkgs and home-manager, the
  module definition is the schema. Documentation lags; code does not.
- **Prefer local over remote.** `kubectl explain`, `--help`, and the vendored
  source in `/nix/store` describe your machine. A web page describes someone
  else's.
- **One authoritative source beats three blog posts.** Stack Overflow answers
  and tutorials are usually pinned to an older version and reproduce each
  other's mistakes.
- **Say what you checked.** When a decision rests on documentation, name the
  source and the version. "Per the home-manager module at `modules/programs/
  opencode.nix`, `skills` accepts a path" is verifiable; "I believe it accepts
  a path" is not.
- **If you could not verify it, say so.** An explicit "I could not confirm this
  option exists in the version you have" is far more useful than a confident
  guess that happens to be wrong.
