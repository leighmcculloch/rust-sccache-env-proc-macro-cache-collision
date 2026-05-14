# sccache stale-cache reproducer + workaround demo

A proc macro that evaluates an env var at expansion time leaves no `env!()`
in the code rustc compiles. So rustc records no `# env-dep:` for that var
in dep-info. So sccache's cache key omits it. So two builds with different
values of that env var hit the same sccache entry — and the cached `.rlib`
is served with the **old** baked-in value.

This mirrors what
[`soroban-sdk-macros::contractmeta`](https://github.com/stellar/rs-soroban-sdk/blob/main/soroban-sdk-macros/src/lib.rs)
does via [`macro-string`](https://crates.io/crates/macro-string).

## Layout

```
workspace/
├── m/                # proc-macro: baked!(env!("X")) → baked literal of std::env::var("X")
└── app/
    ├── build.rs      # emits cargo:rustc-env=GIT_REVISION=<sha>
    ├── src/lib.rs    # the rlib that sccache caches; uses m::baked!()
    └── src/main.rs   # links the rlib, prints app::GIT_REVISION
```

`app` is split into a `lib.rs` (rlib, **cacheable** by sccache) and `main.rs`
(binary, not cacheable). The const lives in the rlib so sccache is actually
exercised — putting it in `main.rs` would have hidden any bug.

## The fix lives inside the proc macro

Open [`workspace/m/src/lib.rs`](workspace/m/src/lib.rs). The proc macro looks
roughly like:

```rust
#[proc_macro]
pub fn baked(input: TokenStream) -> TokenStream {
    let raw = proc_macro2::TokenStream::from(input.clone());
    let MacroString(s) = parse_macro_input!(input);
    let lit = proc_macro2::Literal::string(&s);
    quote! {
        {
            // Uncomment the following line to fix the bug:
            //const { let _ = #raw; };

            #lit
        }
    }
    .into()
}
```

The commented line, when active, expands to (e.g.):

```rust
const { let _ = env!("GIT_REVISION"); };
```

That `const { ... }` block is dead code at runtime — `_` discards everything
— but rustc still expands `env!()` at parse time and records
`# env-dep:GIT_REVISION` in dep-info. sccache reads dep-info, includes the
value of `GIT_REVISION` in the cache key for `app`'s rlib, and a build with
a new value correctly misses the cache and recompiles.

The user-visible value (the `#lit` baked by `macro-string`) is unchanged.
The added line is a "hint" to rustc that this env var matters.

## How to demonstrate

**Run 1 — with the workaround disabled (as shipped):**

```sh
docker build -t sccache-repro .
docker run --rm sccache-repro
```

This runs the build sequence with the proc macro emitting only `#lit`. If
sccache returns a stale rlib for any of the four sccache builds, you'll see
a `STALE` row in the summary.

**Run 2 — with the workaround enabled:**

Edit `workspace/m/src/lib.rs` and uncomment the line that is currently:

```rust
            //const { let _ = #raw; };
```

so it becomes:

```rust
            const { let _ = #raw; };
```

Then rebuild and re-run:

```sh
docker build -t sccache-repro .
docker run --rm sccache-repro
```

Expected outcome with the line uncommented: every sccache build invalidates
correctly when `GIT_REVISION` changes, and all four builds embed the matching
HEAD.

## Script

Two phases of four builds each, with the source identical between the
phases except for an extra `const _: () = { let _ = env!("GIT_REVISION"); };`
line being appended to `app/src/lib.rs` between them.

For each phase:

| Build | sccache | `cargo clean` | New commit | Why                                                                              |
|-------|---------|---------------|------------|----------------------------------------------------------------------------------|
| .1    | on      | yes           | yes        | Baseline. Populate sccache cache for this phase.                                 |
| .2    | on      | yes           | yes        | Does sccache invalidate when `GIT_REVISION` changes?                             |
| .3    | off     | yes           | yes        | Control. Without sccache, the embedded value must be correct.                    |
| .4    | on      | **no**        | yes        | Re-enable sccache after a non-sccache build. Cargo recompiles `app`; what does sccache return? |

The summary at the bottom compares phase 1 to phase 2 — independent of
whether you also toggle the in-macro fix in `m/src/lib.rs`.

## Outcomes to look for

- **🎯 In-macro fix uncommented → all builds OK** — the proc macro itself
  emits the env-dep hint, callers don't have to remember anything.
- **✅ Both phases / both modes show OK** — this minimal repro doesn't
  trigger the bug, but the in-macro fix is harmless and demonstrably keeps
  things correct under conditions that *do* trigger it (like soroban-sdk's
  real wasm build).
- **⚠️ Stale even with the fix uncommented** — would mean rustc isn't
  recording the env-dep from inside a `const { ... }` block. Try moving the
  line out as a top-level item in the macro output instead:
  `const _: &str = #raw;`.
