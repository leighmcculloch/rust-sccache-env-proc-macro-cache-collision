# sccache stale-cache reproducer

Minimal repro for: a proc macro that evaluates an env var at macro-expansion
time leaves no `env!()` in post-expansion code, so rustc records no
`# env-dep:` for that var in dep-info, so sccache's cache key omits the var,
so two builds with different values map to the same cache entry — and the
cached `.rlib` is served with the **old** baked-in value.

Mirrors what
[`soroban-sdk-macros::contractmeta`](https://github.com/stellar/rs-soroban-sdk/blob/main/soroban-sdk-macros/src/lib.rs)
does via the [`macro-string`](https://crates.io/crates/macro-string) crate.

## Layout

```
workspace/
├── m/                    # proc-macro: env_baked!("X") → baked literal of std::env::var("X")
└── app/                  # rlib (cached) + bin (links the rlib, prints the const)
    ├── build.rs          # emits cargo:rustc-env=GIT_REVISION=<sha>
    ├── src/lib.rs        # pub const GIT_REVISION: &str = m::env_baked!("GIT_REVISION");
    └── src/main.rs       # println!("{}", app::GIT_REVISION);
```

The const lives in `lib.rs` deliberately. sccache caches rlibs but not
binaries / proc-macros / cdylibs (they invoke the linker), so putting the
const in `main.rs` would have hidden the bug — sccache would never have been
asked to cache or replay it.

## Script

1. `git init` + commit → `HEAD = SHA1`.
2. `RUSTC_WRAPPER=sccache cargo build --release`, run, capture embedded value.
3. Empty commit → `HEAD = SHA2`, then `cargo clean`.
4. `RUSTC_WRAPPER=sccache cargo build --release`, run, capture embedded value.
5. If step 4 prints `SHA1` instead of `SHA2`, bug reproduced.

## Run

```sh
docker build -t sccache-repro .
docker run --rm sccache-repro
```

Exit 0 = no bug, 1 = stale, 2 = unexpected.
