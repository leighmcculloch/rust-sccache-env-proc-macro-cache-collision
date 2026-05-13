// Only the proc-macro-baked form. There is no `env!()` left in this file
// after macro expansion, so rustc will not record any env-dep on
// GIT_REVISION in dep-info, so sccache's cache key for this crate will
// not include the value of GIT_REVISION.
pub const GIT_REVISION_BAKED: &str = mymacro::baked!(env!("GIT_REVISION"));
