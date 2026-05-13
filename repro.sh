#!/usr/bin/env bash
set -euo pipefail

WORK=/tmp/work
rm -rf "$WORK"
cp -a /repro/workspace "$WORK"
cd "$WORK"

git init -q -b main
git config user.email r@r
git config user.name  r
git add -A && git commit -q -m one
SHA1=$(git rev-parse HEAD)

sccache --stop-server >/dev/null 2>&1 || true
sccache --start-server

stats() { sccache --show-stats | grep -E "^Cache hits|^Cache misses" || true; }

run_build_sccache() {
    sccache --zero-stats >/dev/null
    RUSTC_WRAPPER=sccache cargo build --release --quiet
}

run_build_no_sccache() {
    cargo build --release --quiet
}

# ----------------------------------------------------------------------
echo "===== Build #1: sccache, fresh, HEAD=$SHA1 ====="
run_build_sccache
EMB1=$(./target/release/app)
echo "  expected: $SHA1"
echo "  embedded: $EMB1"
stats

# ----------------------------------------------------------------------
git commit --allow-empty -q -m two
SHA2=$(git rev-parse HEAD)
cargo clean
echo
echo "===== Build #2: sccache, after commit + clean, HEAD=$SHA2 ====="
run_build_sccache
EMB2=$(./target/release/app)
echo "  expected: $SHA2"
echo "  embedded: $EMB2"
stats

# ----------------------------------------------------------------------
git commit --allow-empty -q -m three
SHA3=$(git rev-parse HEAD)
cargo clean
echo
echo "===== Build #3: NO sccache, after commit + clean, HEAD=$SHA3 ====="
run_build_no_sccache
EMB3=$(./target/release/app)
echo "  expected: $SHA3"
echo "  embedded: $EMB3"

# ----------------------------------------------------------------------
git commit --allow-empty -q -m four
SHA4=$(git rev-parse HEAD)
# NOTE: no `cargo clean` here — target/ has build #3's rlib; the new
# commit changes .git/index, build script reruns, env var is now SHA4,
# cargo recompiles app, rustc is invoked, sccache is queried.
echo
echo "===== Build #4: sccache RE-ENABLED, NO clean, new commit, HEAD=$SHA4 ====="
run_build_sccache
EMB4=$(./target/release/app)
echo "  expected: $SHA4"
echo "  embedded: $EMB4"
echo "  build.rs's persisted output:"
grep GIT_REVISION target/release/build/app-*/output | sed 's/^/    /'
stats

# ----------------------------------------------------------------------
echo
echo "===== Summary ====="
verdict() { [ "$1" = "$2" ] && echo "OK" || echo "STALE (got $1, want $2)"; }
printf '  HEAD #1: %s\n' "$SHA1"
printf '  HEAD #2: %s\n' "$SHA2"
printf '  HEAD #3: %s\n' "$SHA3"
printf '  HEAD #4: %s (current)\n' "$SHA4"
echo
printf '  Build #1  sccache,    clean,   HEAD=#1: %s   [%s]\n' "$EMB1" "$(verdict "$EMB1" "$SHA1")"
printf '  Build #2  sccache,    clean,   HEAD=#2: %s   [%s]\n' "$EMB2" "$(verdict "$EMB2" "$SHA2")"
printf '  Build #3  no sccache, clean,   HEAD=#3: %s   [%s]\n' "$EMB3" "$(verdict "$EMB3" "$SHA3")"
printf '  Build #4  sccache,    no clean, HEAD=#4: %s   [%s]\n' "$EMB4" "$(verdict "$EMB4" "$SHA4")"

echo
if [ "$EMB2" != "$SHA2" ] || [ "$EMB4" != "$SHA4" ]; then
    echo "🐛 stale cache observed in build(s) using sccache."
    exit 1
else
    echo "✅ all four builds embedded the correct HEAD."
    exit 0
fi
