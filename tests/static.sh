#!/usr/bin/env bash
# shellcheck disable=SC2015
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "shell syntax"
for f in scripts/*.sh tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s bash scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config >/dev/null; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
df=$(cat Dockerfile)
assert_contains "upstream pinned by tag and digest" 'openai-whisper-asr-webservice:v1.10.0@sha256:' "$df"
assert_contains "Caddy pinned by tag and digest" 'caddy:2.10-alpine@sha256:' "$df"
assert_contains "entrypoint is the wrapper" 'ENTRYPOINT \["/usr/local/bin/whisper-asr-railway-entrypoint"\]' "$df"
assert_contains "webservice bound to loopback in the image" 'WHISPER_HOST=127.0.0.1' "$df"
# The GPU image is ten gigabytes and needs hardware Railway does not sell on standard plans.
if grep -q -- '-gpu' Dockerfile; then fail "a GPU image tag is pinned; Railway has no GPU on standard plans"; else pass "the CPU image is pinned"; fi
if grep -qE '^\s+PORT=' Dockerfile; then fail "PORT must not be baked in; it would shadow the platform's PORT"; else pass "public port left to the entrypoint"; fi

section "the front door cannot be configured away"
ep=$(cat scripts/entrypoint.sh)
assert_contains "refuses a non-loopback WHISPER_HOST" 'binds the webservice to loopback on purpose' "$ep"
assert_contains "requires a password unless explicitly opted out" 'missing required variable: WHISPER_AUTH_PASSWORD' "$ep"
assert_contains "only the health route skips authentication" 'handle /healthz' "$ep"
assert_contains "everything else is behind basic auth" 'basic_auth' "$ep"
assert_contains "the health route publishes no response body" 'respond "ok" 200' "$ep"
assert_contains "the generated config is validated before use" 'caddy validate' "$ep"
assert_contains "uploads are capped" 'max_size' "$ep"
# Railway colours a log line by the stream it arrived on, so routine start-up messages written to
# stderr are shown to the deployer as errors.
if grep -q '^log()' scripts/entrypoint.sh && ! grep '^log()' scripts/entrypoint.sh | grep -q '>&2'; then
  pass "routine logs go to stdout"
else
  fail "log() writes to stderr; Railway would show every start-up line as an error"
fi
if grep '^fail()' scripts/entrypoint.sh | grep -q '>&2'; then
  pass "failures go to stderr"
else
  fail "fail() does not write to stderr"
fi

section "workflows"
# a stale image-override name from a copied workflow makes CI test the wrong image, and the failure
# looks like a missing local build rather than a configuration mistake
override=$(grep -oE '[A-Z_]*_RAILWAY_IMAGE' compose.yaml | head -1)
for wf in .github/workflows/*.yml; do
  if grep -q 'candidate' "$wf" && ! grep -q "$override" "$wf"; then
    fail "$wf tests a candidate image but never sets $override"
  else
    pass "image override name matches compose in $wf"
  fi
done
for wf in .github/workflows/*.yml; do
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: .*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|xox[baprs]-|hf_[A-Za-z0-9]{30,})' -- . >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
