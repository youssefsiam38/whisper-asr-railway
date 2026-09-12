#!/bin/bash
# whisper-asr-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. put the webservice on loopback and Caddy, with HTTP basic authentication, on the public port
#   3. supervise both; if either exits, the container exits
#
# Whisper ASR Webservice has no authentication of its own: app/webservice.py registers `/`, `/asr`
# and `/detect-language`, and none of them checks a credential. On a private network that is fine.
# On a public URL it is an open transcription service running on the deployer's account, so the
# wrapper supplies the boundary upstream assumes is already there.
set -uo pipefail

log()  { printf '[whisper-asr-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${WHISPER_HOST:=127.0.0.1}"
: "${WHISPER_INTERNAL_PORT:=9000}"
: "${WHISPER_AUTH_USERNAME:=admin}"
: "${WHISPER_MAX_UPLOAD_MB:=512}"
: "${ASR_ENGINE:=openai_whisper}"
: "${ASR_MODEL:=base}"
CADDYFILE=/etc/whisper-asr-railway/Caddyfile

# The public listener takes the platform's PORT. Railway probes its healthcheck against that value
# (8080 when unset), so an app that ignores PORT is reported unhealthy however well it serves.
PUBLIC_PORT="${PORT:-8000}"
case "$PUBLIC_PORT" in
  ''|*[!0-9]*) fail "PORT must be a number, got \"$PUBLIC_PORT\"" ;;
esac
case "$WHISPER_INTERNAL_PORT" in
  ''|*[!0-9]*) fail "WHISPER_INTERNAL_PORT must be a number, got \"$WHISPER_INTERNAL_PORT\"" ;;
esac
if [ "$PUBLIC_PORT" = "$WHISPER_INTERNAL_PORT" ]; then
  fail "PORT and WHISPER_INTERNAL_PORT are both $PUBLIC_PORT. The public listener and the webservice cannot share a port; change WHISPER_INTERNAL_PORT."
fi

case "$WHISPER_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) fail "WHISPER_HOST is \"$WHISPER_HOST\". This image binds the webservice to loopback on purpose: it has no authentication, and exposing it directly would publish an open transcription endpoint. Remove the variable." ;;
esac

case "$WHISPER_MAX_UPLOAD_MB" in
  ''|*[!0-9]*) fail "WHISPER_MAX_UPLOAD_MB must be a number, got \"$WHISPER_MAX_UPLOAD_MB\"" ;;
esac
[ "$WHISPER_MAX_UPLOAD_MB" -ge 1 ] || fail "WHISPER_MAX_UPLOAD_MB must be at least 1"

case "$ASR_ENGINE" in
  openai_whisper|faster_whisper|whisperx) ;;
  *) fail "ASR_ENGINE is \"$ASR_ENGINE\". Supported values are openai_whisper, faster_whisper and whisperx." ;;
esac
if [ "$ASR_ENGINE" = "whisperx" ] && [ -z "${HF_TOKEN:-}" ]; then
  fail "ASR_ENGINE=whisperx needs HF_TOKEN to download its diarization model. Upstream only prints a notice and then fails later during transcription, so this image stops here instead. Set HF_TOKEN or choose another engine."
fi
# Only the bundled openai-whisper engine has a fixed catalogue; the other engines accept arbitrary
# Hugging Face repository ids, so they are left alone.
if [ "$ASR_ENGINE" = "openai_whisper" ]; then
  case "$ASR_MODEL" in
    tiny|tiny.en|base|base.en|small|small.en|medium|medium.en) ;;
    large|large-v1|large-v2|large-v3|large-v3-turbo|turbo) ;;
    *) fail "ASR_MODEL is \"$ASR_MODEL\", which openai-whisper does not publish. Choose one of: tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large-v1, large-v2, large-v3, large, large-v3-turbo, turbo." ;;
  esac
  case "$ASR_MODEL" in
    large*|medium*|turbo) log "WARNING: ASR_MODEL=$ASR_MODEL is a large model. The first start downloads several gigabytes and transcription on a CPU-only plan will be slow; \"base\" or \"small\" is the usual choice here." ;;
  esac
fi

ALLOW_PUBLIC="${WHISPER_ALLOW_PUBLIC:-false}"
if [ "$ALLOW_PUBLIC" != "true" ]; then
  [ -n "${WHISPER_AUTH_PASSWORD:-}" ] || fail "missing required variable: WHISPER_AUTH_PASSWORD. Whisper ASR Webservice has no authentication of its own, so without this anyone who finds the URL can run transcriptions on your instance. Set a password, or set WHISPER_ALLOW_PUBLIC=true if you really want an open endpoint."
  [ "${#WHISPER_AUTH_PASSWORD}" -ge 12 ] || fail "WHISPER_AUTH_PASSWORD must be at least 12 characters"
  [ -n "$WHISPER_AUTH_USERNAME" ] || fail "WHISPER_AUTH_USERNAME must not be empty"
fi

# The model cache is the only durable state. Railway mounts the volume as root and this image runs
# as root, so there is nothing to chown -- but the directory has to exist before the app imports.
: "${ASR_MODEL_PATH:=/root/.cache/whisper}"
mkdir -p "$ASR_MODEL_PATH" "${HF_HOME:-/root/.cache/huggingface}" || fail "cannot create the model cache directory"

emit_caddyfile() {
  cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
	request_body {
		max_size ${WHISPER_MAX_UPLOAD_MB}MB
	}
EOF
  if [ "$ALLOW_PUBLIC" = "true" ]; then
    cat >> "$CADDYFILE" <<EOF
	reverse_proxy 127.0.0.1:${WHISPER_INTERNAL_PORT}
}
EOF
  else
    cat >> "$CADDYFILE" <<EOF

	# The platform healthcheck has no credentials to offer. This route asks the webservice for its
	# own OpenAPI document, so it reports whether the model has finished loading, and then throws
	# the body away: callers see a status word and nothing else.
	handle /healthz {
		rewrite * /openapi.json
		reverse_proxy 127.0.0.1:${WHISPER_INTERNAL_PORT} {
			@up status 2xx
			handle_response @up {
				respond "ok" 200
			}
			@down status 3xx 4xx 5xx
			handle_response @down {
				respond "unavailable" 503
			}
		}
	}

	handle {
		basic_auth {
			${WHISPER_AUTH_USERNAME} ${1}
		}
		reverse_proxy 127.0.0.1:${WHISPER_INTERNAL_PORT}
	}
}
EOF
  fi
}

if [ "$ALLOW_PUBLIC" = "true" ]; then
  log "WARNING: WHISPER_ALLOW_PUBLIC=true. Authentication is disabled and anyone who reaches this URL can submit audio for transcription."
  emit_caddyfile ""
else
  hash=$(caddy hash-password --plaintext "$WHISPER_AUTH_PASSWORD" 2>/dev/null) \
    || fail "could not hash WHISPER_AUTH_PASSWORD"
  [ -n "$hash" ] || fail "empty password hash"
  emit_caddyfile "$hash"
  unset hash
  log "authentication enabled for user \"${WHISPER_AUTH_USERNAME}\" (password length ${#WHISPER_AUTH_PASSWORD})"
fi
chmod 600 "$CADDYFILE"
caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 \
  || fail "generated Caddy configuration is invalid"

# Caddy starts first. Loading a Whisper model takes minutes on a cold volume, and a locked front
# door that answers 503 tells the platform far more than a refused connection does. Nothing is
# reachable before it: the credential is already in the config Caddy is reading.
log "opening the public listener on :${PUBLIC_PORT} (upload limit ${WHISPER_MAX_UPLOAD_MB} MB)"
caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

log "starting Whisper ASR Webservice on ${WHISPER_HOST}:${WHISPER_INTERNAL_PORT} with engine ${ASR_ENGINE} and model ${ASR_MODEL}"
export ASR_ENGINE ASR_MODEL ASR_MODEL_PATH
cd /app || fail "cannot enter /app"
whisper-asr-webservice --host "$WHISPER_HOST" --port "$WHISPER_INTERNAL_PORT" &
app_pid=$!

# Announce readiness for the logs. The health route already reports the real state, so this loop
# never gates traffic; it only turns "still downloading" into something a deployer can read.
: "${APP_READY_TIMEOUT:=900}"
ready() {
  python3 - "$1" <<'PYEOF' 2>/dev/null
import sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=5) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PYEOF
}
(
  deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
  until ready "http://127.0.0.1:${WHISPER_INTERNAL_PORT}/openapi.json"; do
    kill -0 "$app_pid" 2>/dev/null || exit 0
    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "WARNING: the model has not finished loading after ${APP_READY_TIMEOUT}s; the health route keeps reporting unavailable"
      exit 0
    fi
    sleep 3
  done
  log "model ${ASR_MODEL} loaded; the service is ready"
) &

stopping=false
trap 'stopping=true; kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null' TERM INT
wait -n "$app_pid" "$caddy_pid"
status=$?
if [ "$stopping" = true ]; then
  log "stopped on signal"
  status=0
else
  log "a supervised process exited with status ${status}; shutting down"
fi
kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null
wait 2>/dev/null
exit "$status"
