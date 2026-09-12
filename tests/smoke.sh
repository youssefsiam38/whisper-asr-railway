#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set WHISPER_ASR_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_PASSWORD='local-test-only-whisper-password'
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' "$LOCAL_PASSWORD" > "$CREDS_FILE"
AUDIO="$TEST_TMP/sample.wav"; make_wav "$AUDIO" 2

section "fresh stack (empty model cache)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
# The front door answers immediately and reports the app as unavailable until the model has been
# fetched and loaded, so the platform holds the deployment instead of cutting over to it.
early=000
for _ in $(seq 1 60); do early=$(http_code --max-time 5 "$BASE_URL/healthz" || true); [ "$early" != "000" ] && break; sleep 1; done
case "$early" in
  502|503) pass "the front door is up before the model is, reporting $early" ;;
  200)     fail "health route reported ready while the model was still loading" ;;
  *)       fail "health route answered $early during start-up" ;;
esac
assert_eq "and it refuses anonymous traffic from that first moment" "401" "$(http_code "$BASE_URL/docs")"
wait_for_code "$BASE_URL/healthz" 200 600 && pass "health route turns healthy once the model loads" || { compose logs --no-color whisper | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "start-up"
wait_for_log "loaded; the service is ready" whisper 120 || true
logs=$(compose logs --no-color whisper)
assert_contains "authentication was enabled" "authentication enabled for user" "$logs"
assert_contains "the door opened before the model finished" "opening the public listener" "$logs"
assert_contains "readiness announced" "loaded; the service is ready" "$logs"
assert_contains "engine and model reported" "engine openai_whisper and model tiny" "$logs"
assert_not_contains "password not in logs" "$LOCAL_PASSWORD" "$logs"
# shellcheck disable=SC2016  # a bcrypt prefix, not a shell expansion
assert_not_contains "password hash not in logs" '\$2a\$' "$logs"

section "anonymous visitors are refused"
# Upstream has no authentication: without the front door every one of these succeeds.
assert_eq "index refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "api docs refused" "401" "$(http_code "$BASE_URL/docs")"
assert_eq "openapi schema refused" "401" "$(http_code "$BASE_URL/openapi.json")"
assert_eq "transcription refused" "401" "$(http_code -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/asr?output=json")"
assert_eq "language detection refused" "401" "$(http_code -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/detect-language")"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/docs")"
assert_eq "wrong username refused" "401" "$(http_code -u "nobody:$LOCAL_PASSWORD" "$BASE_URL/docs")"
assert_eq "health route stays open for the platform probe" "200" "$(http_code "$BASE_URL/healthz")"
assert_eq "health route publishes a status word and nothing else" "ok" "$(curl -s --max-time 20 "$BASE_URL/healthz")"
assert_not_contains "health route does not leak the api schema" "openapi" "$(curl -s --max-time 20 "$BASE_URL/healthz")"

section "the webservice is not reachable except through the front door"
# curl still prints 000 through -w when it cannot connect, so `|| true` rather than `|| echo`
assert_eq "internal port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:9000/openapi.json" || true)"
listeners=$(compose exec -T whisper python3 -c "
import socket
for port in (8000, 9000):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(('0.0.0.0', port)); print(f'{port} free')
    except OSError:
        print(f'{port} taken')
    finally:
        s.close()
" 2>/dev/null || echo "")
assert_contains "public port is bound inside the container" "8000 taken" "$listeners"
assert_contains "internal port is bound inside the container" "9000 taken" "$listeners"

section "authenticated workflow: transcribe and detect"
assert_eq "api docs served" "200" "$(auth_code "$BASE_URL/docs")"
schema=$(openapi)
assert_eq "asr endpoint published" "true" "$(jq -r 'has("/asr")' <<<"$(jq -c .paths <<<"$schema")")"
assert_eq "detect-language endpoint published" "true" "$(jq -r 'has("/detect-language")' <<<"$(jq -c .paths <<<"$schema")")"
assert_eq "upstream version reported" "1.10.0" "$(jq -r .info.version <<<"$schema")"

body=$(transcribe "$AUDIO" "output=json")
assert_eq "transcription returns json" "true" "$(jq -e 'has("text")' >/dev/null 2>&1 <<<"$body" && echo true || echo false)"
assert_eq "segments returned as a list" "array" "$(jq -r '.segments | type' <<<"$body")"
assert_eq "language reported" "string" "$(jq -r '.language | type' <<<"$body")"

txt=$(curl -s -o /dev/null -w '%{http_code} %{content_type}' --max-time 300 -u "$(creds)" \
  -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/asr?output=txt")
assert_contains "plain-text output served" "200 text/plain" "$txt"

srt_code=$(auth_code -X POST -F "audio_file=@${AUDIO};type=audio/wav" "$BASE_URL/asr?output=srt")
assert_eq "subtitle output served" "200" "$srt_code"

d=$(detect_language "$AUDIO")
assert_eq "language detection returns a code" "string" "$(jq -r '.language_code | type' <<<"$d")"
assert_eq "detection confidence returned" "number" "$(jq -r '.confidence | type' <<<"$d")"

section "uploads are bounded"
big="$TEST_TMP/big.wav"; make_wav "$big" 40   # ~1.2 MB of PCM
img=$(compose config --images | head -1)
docker rm -f whisper-small-cap >/dev/null 2>&1 || true
# Share the model already downloaded by the running stack, so this instance is ready in seconds.
# Caddy only reports the limit once the request reaches a handler that reads the body, so the
# webservice has to be listening or this measures a cold start instead of the cap.
cache_vol=$(docker inspect "$(compose ps -q whisper)" \
  --format '{{range .Mounts}}{{if eq .Destination "/root/.cache"}}{{.Name}}{{end}}{{end}}')
docker run -d --name whisper-small-cap -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e WHISPER_MAX_UPLOAD_MB=1 \
  -e ASR_MODEL=tiny -e PORT=8020 -p 127.0.0.1:8020:8020 -v "${cache_vol}:/root/.cache" "$img" >/dev/null
wait_for_code "http://127.0.0.1:8020/healthz" 200 300 || die "the capped instance never became ready"
cap=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -u "$(creds)" \
  -X POST -F "audio_file=@${big};type=audio/wav" "http://127.0.0.1:8020/asr?output=json" || true)
assert_eq "an upload over the cap is rejected" "413" "$cap"
under=$(curl -s -o /dev/null -w '%{http_code}' --max-time 120 -u "$(creds)" \
  -X POST -F "audio_file=@${AUDIO};type=audio/wav" "http://127.0.0.1:8020/asr?output=json" || true)
assert_eq "an upload under the cap still works" "200" "$under"
docker rm -f whisper-small-cap >/dev/null

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 whisper; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q whisper)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start whisper; wait_for_code "$BASE_URL/healthz" 200 600 && pass "restarted" || die "did not restart"

section "fail-fast validation"
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img; then fail "should fail without a password"; else pass "exits without WHISPER_AUTH_PASSWORD"; fi
assert_contains "explains why a password is required" "anyone who finds the URL can run transcriptions" "$(cat "$TEST_TMP/ff.log")"
if run_img -e WHISPER_AUTH_PASSWORD=short; then fail "should reject a short password"; else pass "rejects a short password"; fi
assert_contains "states the length rule" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e WHISPER_HOST=0.0.0.0; then fail "should refuse to unbind from loopback"; else pass "refuses a non-loopback WHISPER_HOST"; fi
assert_contains "explains the loopback rule" "open transcription endpoint" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e PORT=9000; then fail "should refuse a port collision"; else pass "refuses a port collision with the webservice"; fi
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e ASR_MODEL=enormous; then fail "should reject an unknown model"; else pass "rejects an unknown ASR_MODEL"; fi
assert_contains "lists the models that exist" "openai-whisper does not publish" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e ASR_ENGINE=whisperx; then fail "should reject whisperx without a token"; else pass "rejects whisperx with no HF_TOKEN"; fi
assert_contains "explains the whisperx requirement" "needs HF_TOKEN" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "WHISPER_AUTH_PASSWORD=$LOCAL_PASSWORD" -e ASR_ENGINE=nonsense; then fail "should reject an unknown engine"; else pass "rejects an unknown ASR_ENGINE"; fi
assert_contains "lists the engines that exist" "openai_whisper, faster_whisper and whisperx" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed" "$LOCAL_PASSWORD" "$(cat "$TEST_TMP/ff.log")"

section "the opt-out is deliberate and loud"
docker rm -f whisper-open >/dev/null 2>&1 || true
docker run -d --name whisper-open -e WHISPER_ALLOW_PUBLIC=true -e ASR_MODEL=tiny -e PORT=8010 -p 127.0.0.1:8010:8010 "$img" >/dev/null
for _ in $(seq 1 120); do [ "$(http_code --max-time 5 "http://127.0.0.1:8010/docs" || true)" = "200" ] && break; sleep 3; done
assert_eq "open instance serves anonymously" "200" "$(http_code "http://127.0.0.1:8010/docs")"
assert_contains "and says so in the log" "Authentication is disabled" "$(docker logs whisper-open 2>&1)"
docker rm -f whisper-open >/dev/null

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.whisper-asr-railway.upstream.version io.whisper-asr-railway.caddy.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "upstream licence shipped" "MIT License" "$(compose exec -T whisper head -1 /usr/share/licenses/whisper-asr-railway/WHISPER-ASR-LICENSE | tr -d '\r')"
assert_contains "Caddy licence shipped" "Apache License" "$(compose exec -T whisper sed -n '2p' /usr/share/licenses/whisper-asr-railway/CADDY-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep whisper-asr-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
