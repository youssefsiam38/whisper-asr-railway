#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: CREDS_FILE=/path/to/file holding "username:password"
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}
AUDIO="$TEST_TMP/sample.wav"; make_wav "$AUDIO" 2

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over, so wait rather than
# racing the cutover when this runs straight after a deploy.
wait_for_code "$BASE_URL/healthz" 200 600 || true
assert_eq "health route answers over https" "200" "$(http_code "$BASE_URL/healthz")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/healthz" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/healthz")"

section "the instance is not open to the internet"
assert_eq "index refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "api docs refused" "401" "$(http_code "$BASE_URL/docs")"
assert_eq "openapi schema refused" "401" "$(http_code "$BASE_URL/openapi.json")"
assert_eq "transcription refused" "401" "$(http_code -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/asr?output=json")"
assert_eq "language detection refused" "401" "$(http_code -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/detect-language")"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/docs")"
assert_eq "health route publishes a status word and nothing else" "ok" "$(curl -s --max-time 20 "$BASE_URL/healthz")"

if [ -n "${CREDS_FILE:-}" ]; then
  section "signed in through the public domain"
  assert_eq "api docs served" "200" "$(auth_code "$BASE_URL/docs")"
  schema=$(openapi)
  assert_eq "upstream version reported" "1.10.0" "$(jq -r .info.version <<<"$schema")"
  assert_eq "asr endpoint published" "true" "$(jq -r '.paths | has("/asr")' <<<"$schema")"

  section "transcribe through the public domain"
  body=$(transcribe "$AUDIO" "output=json")
  assert_eq "transcription returns json" "true" "$(jq -e 'has("text")' >/dev/null 2>&1 <<<"$body" && echo true || echo false)"
  assert_eq "segments returned as a list" "array" "$(jq -r '.segments | type' <<<"$body")"
  d=$(detect_language "$AUDIO")
  assert_eq "language detection returns a code" "string" "$(jq -r '.language_code | type' <<<"$d")"
fi
summary
