# sccache stale-cache reproducer + workaround demo

An example of how using macro-string inside a proc-macro when building with
sccache can result in stale build artifacts being served with `env!` loaded env
vals not being used in the final build.

A proc macro that evaluates an env var at expansion time leaves no `env!()`
in the code rustc compiles. So rustc records no `# env-dep:` for that var
in dep-info. So sccache's cache key omits it. So two builds with different
values of that env var hit the same sccache entry — and the cached `.rlib`
is served with the **old** baked-in value.

This mirrors what
[`soroban-sdk-macros::contractmeta`](https://github.com/stellar/rs-soroban-sdk/blob/main/soroban-sdk-macros/src/lib.rs)
does with [`macro-string`](https://crates.io/crates/macro-string) and behaviours we've seen when `contractmeta` is used with `env!`.

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
(binary, not cacheable). The const lives in the rlib so sccache is in use.

## Macro Use

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
            // Uncomment the following line to fix/workaround the bug:
            //const { let _ = #raw; };

            #lit
        }
    }
    .into()
}
```

Any `env!` passed in as part of `input` is evaluated by `parse_macro_input!`
and so no `env!` actually ends up in the final code for the crate that rustc sees,
it does not end up in dep-info and sccache does not include that input as part of the cache key.

The commented line, when active, expands to:

```rust
const { let _ = env!("GIT_REVISION"); };
```

That `const { ... }` block is dead code at runtime but rustc still expands `env!()` at parse time and records
`# env-dep:GIT_REVISION` in dep-info. sccache reads dep-info, includes the
value of `GIT_REVISION` in the cache key for `app`'s rlib, and a build with
a new value correctly misses the cache and recompiles.

The user-visible value (the `#lit` baked by `macro-string`) is unchanged.
The added line is a "hint" to rustc that this env var matters.

## Running the Example

**Run 1 — with the workaround disabled (as exists in the repo):**

```sh
docker build -t repro .
docker run --rm repro
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
correctly when `GIT_REVISION` changes, and all four builds embed the correct
HEAD revision.

## What does this mean?

Still unclear to me what the right fix is here. Every time we use macro-string should we also emit the raw input? Is that always safe to do? Maybe for our use case, maybe not for all use cases.
