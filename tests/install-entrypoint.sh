#!/bin/sh
# Run in a disposable BusyBox container:
# docker run --rm --network none --read-only --tmpfs /tmp:rw,exec --tmpfs /jffs \
#   -v "$PWD:/repo:ro" alpine:3.12 /bin/sh /repo/tests/install-entrypoint.sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
mkdir "$work/bin"
export TEST_FETCH_LOG=$work/downloads TEST_BACKEND_LOG=$work/backend
export TEST_OS=Linux TEST_MODEL=ZenWiFi_ET12 TEST_RESPONSE=ok TEST_BACKEND_STATUS=0
export PATH=$work/bin:$PATH TMPDIR=$work

cat >"$work/bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$TEST_OS"
EOF
cat >"$work/bin/nvram" <<'EOF'
#!/bin/sh
[ "$1" = get ] || exit 1
case "$2" in productid) printf '%s\n' "$TEST_MODEL";; esac
EOF
cat >"$work/bin/sh" <<'EOF'
#!/bin/sh
echo 'bare sh was invoked' >&2
exit 91
EOF
cat >"$work/bin/mktemp" <<'EOF'
#!/bin/sh
echo 'mktemp is unavailable on ASUS firmware' >&2
exit 127
EOF
cat >"$work/bin/bash" <<'EOF'
#!/bin/sh
exec /bin/sh "$@"
EOF
cat >"$work/bin/curl" <<'EOF'
#!/bin/sh
set -eu
output='' url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output=$2; shift 2;;
        https://*) url=$1; shift;;
        *) shift;;
    esac
done
printf '%s\n' "$url" >>"$TEST_FETCH_LOG"
case "$TEST_RESPONSE:$url" in
    fail:*) exit 22;;
    html-first:https://gh-proxy.org/*) echo '<html>mirror error</html>' >"$output"; exit 0;;
    partial-first:https://gh-proxy.org/*) printf '#!/bin/sh\nexit 99\n' >"$output"; exit 18;;
    syntax-first:https://gh-proxy.org/*) printf '#!/bin/sh\nif then\n' >"$output"; exit 0;;
esac
case "$url" in
    */install-asus.sh) printf '#!/bin/sh\n' >"$output";;
    *) printf '#!/usr/bin/env bash\n' >"$output";;
esac
cat >>"$output" <<'BACKEND'
printf 'run\n' >>"$TEST_BACKEND_LOG"
printf '<%s>\n' "$@" >>"$TEST_BACKEND_LOG"
exit "$TEST_BACKEND_STATUS"
BACKEND
EOF
chmod +x "$work/bin/"*

fail() { echo "FAIL: $*" >&2; cat "$work/output" >&2; exit 1; }
reset() {
    : >"$TEST_FETCH_LOG"
    : >"$TEST_BACKEND_LOG"
    TEST_OS=Linux TEST_MODEL=ZenWiFi_ET12 TEST_RESPONSE=ok TEST_BACKEND_STATUS=0
}
run() {
    status=0
    /bin/sh "$repo/install.sh" "$@" >"$work/output" 2>&1 || status=$?
}
expect_status() { [ "$status" -eq "$1" ] || fail "exit $status, expected $1"; }
expect_downloads() { [ "$(wc -l <"$TEST_FETCH_LOG" | tr -d ' ')" -eq "$1" ] || fail "expected $1 downloads"; }
expect_backend() { [ "$(cat "$TEST_BACKEND_LOG")" = "$1" ] || fail 'backend arguments or invocation count differ'; }
pass() { echo "PASS: $*"; }

reset
run --no-menu
expect_status 0
expect_downloads 1
expect_backend 'run
<--no-menu>'
grep -q '^https://gh-proxy.org/https://github.com/.*/install-asus.sh$' "$TEST_FETCH_LOG" || fail 'ASUS route'
pass 'ASUS uses the dedicated POSIX installer, with arguments and absolute /bin/sh'

for response in html-first partial-first syntax-first; do
    reset
    TEST_RESPONSE=$response
    run
    expect_status 0
    expect_downloads 2
    expect_backend 'run
<>'
    grep -q '^https://ghfast.top/' "$TEST_FETCH_LOG" || fail 'fallback mirror'
    pass "$response falls back without executing the bad response"
done

reset
TEST_RESPONSE=fail
run
expect_status 1
expect_downloads 3
expect_backend ''
pass 'all downloads fail without starting an installation'

reset
TEST_BACKEND_STATUS=23
run
expect_status 23
expect_downloads 1
expect_backend 'run
<>'
pass 'backend failure is preserved and never causes another installation'

for option in --uninstall --version --pre-release --mirror; do
    reset
    run "$option"
    expect_status 1
    expect_downloads 0
    expect_backend ''
done
pass 'desktop options cannot reach the ASUS backend or generic uninstaller'

reset
TEST_MODEL=''
run --version v1.104.7 --mirror https://mirror.example
expect_status 0
expect_downloads 1
expect_backend 'run
<--version>
<v1.104.7>
<--mirror>
<https://mirror.example>'
grep -q '^https://mirror.example/https://raw.githubusercontent.com/.*/install-linux.sh$' "$TEST_FETCH_LOG" || fail 'Linux route and custom mirror'
pass 'Linux keeps its version and mirror arguments'

reset
TEST_OS=Darwin
run --uninstall
expect_status 0
expect_backend 'run
<--uninstall>'
grep -q '^https://raw.githubusercontent.com/.*/install-macos.sh$' "$TEST_FETCH_LOG" || fail 'macOS route'
pass 'macOS keeps its native installer and arguments'

reset
TEST_OS=FreeBSD
run
expect_status 1
expect_downloads 0
run --help
expect_status 0
expect_downloads 0
pass 'unsupported systems stop before downloading; help runs offline'

reset
TEST_MODEL=''
mv "$work/bin/bash" "$work/bash"
run
expect_status 1
expect_downloads 0
TEST_MODEL=RT-AXE95Q
run --no-menu
expect_status 0
expect_backend 'run
<--no-menu>'
pass 'desktop requires Bash; ASUS runs without it'

[ -z "$(find "$work" -maxdepth 1 -type d -name 'tailscale-awg-install.*' -print)" ] || fail 'temporary download directories remain'
echo 'All installer entry-point checks passed.'
