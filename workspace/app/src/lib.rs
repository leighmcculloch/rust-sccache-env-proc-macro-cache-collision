// This is the rlib that sccache will cache. The proc macro consumes the
// env var at expansion time and emits a baked string literal here, so
// rustc records no env-dep on GIT_REVISION in dep-info, so sccache's
// cache key for this rlib will not include the value of GIT_REVISION.
pub const GIT_REVISION: &str = m::env_baked!("GIT_REVISION");
