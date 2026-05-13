use macro_string::MacroString;
use proc_macro::TokenStream;
use quote::quote;
use syn::parse_macro_input;

/// Mirrors the pattern in `soroban-sdk-macros::contractmeta`: take an
/// expression that may contain `env!(...)` / `concat!(...)`, evaluate
/// it INSIDE the proc macro using `macro-string`, and emit the result
/// as a baked string literal. After expansion there is no `env!()` left
/// in the token stream rustc compiles, so rustc records no env-dep.
#[proc_macro]
pub fn baked(input: TokenStream) -> TokenStream {
    let MacroString(s) = parse_macro_input!(input);
    let lit = proc_macro2::Literal::string(&s);
    quote! { #lit }.into()
}
