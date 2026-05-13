# sccache stale-cache reproducer — proc-macro env!() pattern

## TL;DR

When a proc macro evaluates `env!("FOO")` **inside the macro itself** (e.g. via
the [`macro-string`](https://crates.io/crates/macro-string) crate) and emits
the resolved value as a baked string literal, the post-expansion code that
rustc compiles contains no `env!()` call. Therefore rustc records no env-dep
on `FOO` in dep-info. Therefore sccache's cache key for that crate does not
include `FOO`. Two builds with the same source but different `FOO` values hit
the same sccache entry, and the second build is served a stale `.rlib`.

This is exactly the pattern in
[`soroban-sdk-macros::contractmeta`](https://github.com/stellar/rs-soroban-sdk/blob/main/soroban-sdk-macros/src/lib.rs):

```rust
let val = args.val.to_token_stream().into();
let MacroString(val) = parse_macro_input!(val);
```

It's not a bug in `sccache` or in `crate-git-revision`. It's a consequence of
how the proc macro consumes `env!()` before rustc ever sees it.

## What this repro builds

Workspace with three crates:

- `mymacro` — proc-macro crate with `baked!()`, the minimal stand-in for
  `contractmeta!`. Uses `macro-string` to evaluate `env!()` inside the macro
  and emit a baked string literal.
- `mylib` — has a `build.rs` that emits `cargo:rustc-env=GIT_REVISION=<sha>`.
  Exposes two constants for comparison:
  - `GIT_REVISION_PLAIN: &str = env!("GIT_REVISION");`           — rustc evaluates
  - `GIT_REVISION_BAKED: &str = mymacro::baked!(env!("GIT_REVISION"));` — proc macro evaluates
- `app` — prints both.

## What the script does

1. `git init` + commit → SHA1.
2. Build with sccache, print both constants.
3. Make an empty commit → SHA2.
4. `cargo clean`.
5. Build with sccache, print both constants.
6. `cargo clean`, build with sccache disabled, print both (control).

If `PLAIN` updates to SHA2 but `BAKED` stays at SHA1, the bug is reproduced.
The control build confirms the issue is sccache-specific.

## Run

```sh
cd sccache-repro
docker build -t sccache-repro .
docker run --rm sccache-repro
```

Exit codes: `0` = no bug, `1` = bug reproduced and isolated, `2` = unexpected.

## What to do about it

Options for soroban-sdk specifically (none affect `crate-git-revision`):

1. **Stop using `MacroString` for the `val` argument.** Emit the `env!()` call
   into the macro output unchanged and let rustc evaluate it. The macro would
   need to defer XDR encoding to runtime, or use a const-eval-friendly XDR
   serializer. Big change.
2. **Add a "synthetic" env!() reference to the proc macro output**, purely so
   rustc records the env-dep. e.g. emit
   `const _: &str = env!("GIT_REVISION");`
   alongside the baked metadata. Smallest possible change, keeps the existing
   encoding, ensures sccache (and any other rustc-wrapper) sees the env-dep.
3. **Document the incompatibility** with rustc-wrapper caches like sccache
   and recommend users disable the wrapper for builds where the embedded
   version matters.

Option 2 is the cleanest fix and worth raising upstream in
[stellar/rs-soroban-sdk](https://github.com/stellar/rs-soroban-sdk).
