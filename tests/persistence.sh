#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the downloaded model survives recreating the container, so a redeploy does not
# re-fetch it. The model cache is the only durable state this service has.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' 'local-test-only-whisper-password' > "$CREDS_FILE"
AUDIO="$TEST_TMP/sample.wav"; make_wav "$AUDIO" 2

section "fresh stack (empty model cache)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/healthz" 200 600 || die "not ready"
cold=$(( $(date +%s) - t0 ))
pass "first start took ${cold}s including the model download"

section "the model landed in the volume"
cached=$(compose exec -T whisper sh -c 'ls -1 /root/.cache/whisper 2>/dev/null' | tr -d '\r')
assert_contains "model file cached" "tiny.pt" "$cached"
body=$(transcribe "$AUDIO" "output=json")
assert_eq "transcription works before the recreate" "true" "$(jq -e 'has("text")' >/dev/null 2>&1 <<<"$body" && echo true || echo false)"

section "recreate the container on the same volume"
compose down >/dev/null
t1=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/healthz" 200 600 || die "not ready after recreate"
warm=$(( $(date +%s) - t1 ))
pass "second start took ${warm}s"

section "verify"
cached=$(compose exec -T whisper sh -c 'ls -1 /root/.cache/whisper 2>/dev/null' | tr -d '\r')
assert_contains "model still cached" "tiny.pt" "$cached"
logs=$(compose logs --no-color whisper --since 1m)
assert_not_contains "the model was not downloaded again" "100%" "$logs"
body=$(transcribe "$AUDIO" "output=json")
assert_eq "transcription still works" "true" "$(jq -e 'has("text")' >/dev/null 2>&1 <<<"$body" && echo true || echo false)"
assert_eq "credentials unchanged" "200" "$(auth_code "$BASE_URL/docs")"
assert_eq "anonymous still refused" "401" "$(http_code "$BASE_URL/docs")"
[ "$warm" -lt "$cold" ] && pass "the warm start was faster than the cold one (${warm}s vs ${cold}s)" \
  || fail "the warm start was not faster (${warm}s vs ${cold}s); the cache may not be persisting"
summary
