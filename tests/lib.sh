#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for whisper-asr-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:8000}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

# CREDS_FILE holds "username:password" and is never printed.
creds() { cat "${CREDS_FILE:?CREDS_FILE not set}"; }

http_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
auth_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -u "$(creds)" "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

# wait_for_log PATTERN [SERVICE] [TIMEOUT] -- the readiness line is written by a background loop
# that polls every few seconds, so it can trail the first healthy response.
wait_for_log() {
  local pattern=$1 service=${2:-whisper} timeout=${3:-120} start
  start=$(date +%s)
  while :; do
    compose logs --no-color "$service" 2>/dev/null | grep -q -- "$pattern" && return 0
    [ $(( $(date +%s) - start )) -ge "$timeout" ] && return 1
    sleep 2
  done
}

# make_wav PATH SECONDS -- a mono 16 kHz PCM tone. ffmpeg is in the image but not necessarily on
# the host, and the stdlib writes a valid RIFF file in a dozen lines.
make_wav() {
  python3 - "$1" "${2:-2}" <<'PYEOF'
import math, struct, sys, wave
path, seconds = sys.argv[1], float(sys.argv[2])
rate = 16000
with wave.open(path, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    frames = bytearray()
    for i in range(int(rate * seconds)):
        # a quiet 220 Hz tone: valid audio that decodes, with no speech to transcribe
        frames += struct.pack("<h", int(3000 * math.sin(2 * math.pi * 220 * i / rate)))
    w.writeframes(bytes(frames))
PYEOF
}

# transcribe FILE [QUERY] -> response body. Always authenticated.
transcribe() {
  local f=$1 q=${2:-output=json}
  curl -s --max-time 300 -u "$(creds)" -X POST -F "audio_file=@${f};type=audio/wav" \
    "$BASE_URL/asr?$q"
}
detect_language() {
  curl -s --max-time 300 -u "$(creds)" -X POST -F "audio_file=@${1};type=audio/wav" \
    "$BASE_URL/detect-language"
}
openapi() { curl -s --max-time 60 -u "$(creds)" "$BASE_URL/openapi.json"; }

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
