#!/usr/bin/env bash
set -euo pipefail

WORK=/tmp/work
rm -rf "$WORK"
cp -a /repro/workspace "$WORK"
cd "$WORK"

git init -q -b main
git config user.email "repro@example.com"
git config user.name  "Repro"
git add -A
git commit -q -m "initial"
SHA1=$(git rev-parse HEAD)

heading() { printf '\n========== %s ==========\n' "$*"; }

extract() {
    grep "^$1=" "$2" | sed "s/^$1=//"
}

dump_dep_info() {
    local d
    d=$(find target -name 'mylib-*.d' -path '*/release/*' 2>/dev/null | head -1)
    if [ -n "$d" ]; then
        echo "  mylib dep-info: $d"
        grep -E "env-dep|^#" "$d" | sed 's/^/    /' || true
    fi
}

dump_stats() {
    sccache --show-stats | grep -E "^Compile requests|^Cache hits|^Cache misses|^Cache writes" || true
}

# ----------------------------------------------------------------------
heading "Build #1 with sccache  (HEAD = $SHA1)"
# ----------------------------------------------------------------------
sccache --stop-server >/dev/null 2>&1 || true
sccache --start-server
sccache --zero-stats >/dev/null

RUSTC_WRAPPER=sccache cargo build --release --bin app 2>&1 | grep -E "Compiling|warning: mylib/build.rs" || true

./target/release/app | tee /tmp/out1.txt
BAKED1=$(extract BAKED /tmp/out1.txt)
echo
dump_dep_info
echo
echo "sccache stats:"
dump_stats

# ----------------------------------------------------------------------
heading "Make a new commit (SHA2), then 'cargo clean'"
# ----------------------------------------------------------------------
git commit --allow-empty -q -m "second"
SHA2=$(git rev-parse HEAD)
echo "  New HEAD: $SHA2"
cargo clean

# ----------------------------------------------------------------------
heading "Build #2 with sccache  (HEAD = $SHA2, after cargo clean)"
# ----------------------------------------------------------------------
sccache --zero-stats >/dev/null

RUSTC_WRAPPER=sccache cargo build --release --bin app 2>&1 | grep -E "Compiling|warning: mylib/build.rs" || true

./target/release/app | tee /tmp/out2.txt
BAKED2=$(extract BAKED /tmp/out2.txt)
echo
echo "  mylib/build.rs's persisted output:"
grep -E "GIT_REVISION" target/release/build/mylib-*/output | sed 's/^/    /'
echo
dump_dep_info
echo
echo "sccache stats:"
dump_stats

# ----------------------------------------------------------------------
heading "Build #3 with sccache DISABLED  (control, HEAD = $SHA2, after cargo clean)"
# ----------------------------------------------------------------------
cargo clean
cargo build --release --bin app 2>&1 | grep -E "Compiling|warning: mylib/build.rs" || true

./target/release/app | tee /tmp/out3.txt
BAKED3=$(extract BAKED /tmp/out3.txt)

# ----------------------------------------------------------------------
heading "Build #4 with sccache RE-ENABLED, NO 'cargo clean', new commit (SHA3)"
# ----------------------------------------------------------------------
git commit --allow-empty -q -m "third"
SHA3=$(git rev-parse HEAD)
echo "  New HEAD: $SHA3"
echo "  (Note: no 'cargo clean' before this build — target/ contains build #3's rlib;"
echo "   the sccache server's cache still has whatever it stored in build #2.)"
echo

sccache --zero-stats >/dev/null

RUSTC_WRAPPER=sccache cargo build --release --bin app 2>&1 | grep -E "Compiling|warning: mylib/build.rs|Fresh" || true

./target/release/app | tee /tmp/out4.txt
BAKED4=$(extract BAKED /tmp/out4.txt)
echo
echo "  mylib/build.rs's persisted output:"
grep -E "GIT_REVISION" target/release/build/mylib-*/output | sed 's/^/    /'
echo
dump_dep_info
echo
echo "sccache stats:"
dump_stats

# ----------------------------------------------------------------------
heading "Summary"
# ----------------------------------------------------------------------
verdict() { [ "$1" = "$2" ] && echo "OK" || echo "STALE ($3)"; }

printf '\n'
printf '  HEAD #1 (initial)                : %s\n' "$SHA1"
printf '  HEAD #2 (after first new commit) : %s\n' "$SHA2"
printf '  HEAD #3 (current)                : %s\n' "$SHA3"
printf '\n'
printf '  Build #1  sccache,  clean,  HEAD=#1  BAKED: %s   [%s]\n' "$BAKED1" "$(verdict "$BAKED1" "$SHA1" "want SHA1")"
printf '  Build #2  sccache,  clean,  HEAD=#2  BAKED: %s   [%s]\n' "$BAKED2" "$(verdict "$BAKED2" "$SHA2" "want SHA2")"
printf '  Build #3  no sccache, clean, HEAD=#2 BAKED: %s   [%s]\n' "$BAKED3" "$(verdict "$BAKED3" "$SHA2" "want SHA2")"
printf '  Build #4  sccache, NO clean, HEAD=#3 BAKED: %s   [%s]\n' "$BAKED4" "$(verdict "$BAKED4" "$SHA3" "want SHA3")"

echo
if [ "$BAKED4" != "$SHA3" ]; then
    echo "🐛 Build #4 returned a stale value (\"$BAKED4\" != current HEAD \"$SHA3\")."
    echo "   This is the scenario from your soroban-sdk session: sccache turned"
    echo "   back on with an existing target/ tree, build script reran with the"
    echo "   new HEAD, but the rlib delivered to the linker was sccache's"
    echo "   stored copy from an earlier compile."
    exit 1
elif [ "$BAKED2" != "$SHA2" ]; then
    echo "🐛 Build #2 reproduced the original bug shape."
    exit 1
else
    echo "✅ All four builds embedded the correct HEAD."
    echo "   The proc-macro pattern alone is not sufficient to reproduce the"
    echo "   stale-cache symptom in this sccache version."
    exit 0
fi
