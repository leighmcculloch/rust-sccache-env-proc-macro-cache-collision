use proc_macro::TokenStream;
use quote::quote;

/// Read the env var at proc-macro expansion time and emit its value as a
/// baked string literal. After expansion there is no `env!()` for rustc
/// to record as a dep-info env-dep, so caching layers that key off
/// dep-info (sccache) won't include this env var in their cache key.
#[proc_macro]
pub fn env_baked(input: TokenStream) -> TokenStream {
    let name = syn::parse_macro_input!(input as syn::LitStr).value();
    let value = std::env::var(&name).unwrap_or_default();
    let lit = proc_macro2::Literal::string(&value);
    quote!(#lit).into()
}
