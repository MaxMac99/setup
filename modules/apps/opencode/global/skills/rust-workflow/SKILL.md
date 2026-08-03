---
name: rust-workflow
description: Use when working in a Rust project - editing .rs files, Cargo.toml, or a Rust workspace - and when verifying, testing, formatting or debugging Rust code. Covers the check/clippy/test loop, the direnv-provided toolchain, and which cargo tools are available.
---

# Rust workflow

## The toolchain comes from the project, not from your PATH

Rust projects here use a per-project `flake.nix` loaded by direnv. When you open
a shell in the project, **direnv has already put the correct toolchain on PATH**.

- Run `cargo` and `rustc` directly. Trust the environment.
- Do **not** run `nix develop` manually, and do not `nix run nixpkgs#cargo`.
  Either can pull in a different toolchain than the project pins.
- If `cargo` is missing or the version looks wrong, direnv has probably not
  allowed the directory. Say so and suggest `direnv allow` — do not work around
  it by reaching for a global toolchain.

## Verification loop

Run in this order, cheapest first, and stop at the first failure:

```
cargo check --all-targets            # fastest signal, catches type errors
cargo clippy --all-targets -- -D warnings
cargo test
```

**Clippy warnings are errors.** `-D warnings` is not optional — treat any lint
as a failure to fix, not advice to weigh. If a lint is genuinely wrong for the
situation, add a scoped `#[allow(...)]` with a comment explaining why, rather
than removing `-D warnings`.

Before proposing a commit, also run:

```
cargo fmt
```

Never hand-format Rust. If `cargo fmt --check` fails, run `cargo fmt` and
include the result in the same logical change.

## Available tooling

On PATH: `rustc`, `cargo`, `cargo-clippy`, `rustfmt`, `rust-analyzer`.

**Not installed:** `cargo-nextest`, `bacon`, `cargo-watch`, `taplo`. Do not
suggest commands that depend on them, and do not silently substitute
`cargo nextest run` for `cargo test`. If a watch loop or a faster runner would
genuinely help, say so and let the user decide whether to add it to
`modules/profiles/development.nix`.

## Workspaces

In a workspace, prefer targeting the crate you changed:

```
cargo check -p <crate>
cargo test -p <crate>
```

Run the full workspace before proposing a commit, since a change in one crate
routinely breaks a sibling.

## Conventions

- Return `Result` rather than panicking in library code. `unwrap()` and
  `expect()` belong in tests, `main`, and cases where a panic is genuinely the
  correct response to a broken invariant — and then `expect()` with a message
  explaining the invariant.
- Prefer `?` over matching solely to re-wrap an error.
- Derive the scope for a commit from the crate name.
- When adding a dependency, check whether the workspace already has something
  equivalent before introducing a second library for the same job.
