// The rlib that sccache will cache. The proc macro consumes the env!()
// invocation at expansion time (via macro-string) and emits a baked
// literal here, so after expansion there is no `env!()` for rustc to
// record as a dep-info env-dep on GIT_REVISION — and sccache's cache
// key for this rlib does not include the value of GIT_REVISION.
pub const GIT_REVISION: &str = m::baked!(env!("GIT_REVISION"));
