use macro_string::MacroString;
use proc_macro::TokenStream;
use quote::quote;
use syn::parse_macro_input;

/// Mirrors `soroban-sdk-macros::contractmeta`: take an expression that may
/// contain `env!(...)` / `concat!(...)`, evaluate it inside the proc macro
/// using `macro-string`, and emit the resolved value as a baked string
/// literal.
///
#[proc_macro]
pub fn baked(input: TokenStream) -> TokenStream {
    // Clone input before parse_macro_input! consumes it; the clone is
    // re-emitted into a const block so rustc sees the original env!()
    // tokens and records env-deps in dep-info.
    let raw = proc_macro2::TokenStream::from(input.clone());
    let MacroString(s) = parse_macro_input!(input);
    let lit = proc_macro2::Literal::string(&s);
    quote! {
        {
            // Fix: re-emit the original input inside a `const { ... }` block, so
            // rustc parses the `env!()` itself and records the corresponding
            // `# env-dep:` line in dep-info. Downstream caches (sccache) read
            // dep-info to know which env vars belong in the cache key — without
            // this, two builds with different env-var values map to the same key
            // and the cached `.rlib` is served stale.
            //
            // Uncommon the following line to see the test pass.
            //const { let _ = #raw; };
            
            // Existing behaviour to just emit the read macro string:
            #lit
        }
    }
    .into()
}
