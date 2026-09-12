# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Whisper ASR Webservice |
| Code | `whisper-asr-webservice` |
| Template id | `1f70dc95-090f-4670-9e5b-53fc2e7436c2` |
| Deploy URL | https://railway.com/deploy/whisper-asr-webservice |
| Category | AI/ML |
| Image | `ghcr.io/youssefsiam38/whisper-asr-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Service `whisper` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/whisper-asr-railway:<version>` |
| Port | 8000 |
| Domain | generated, target port 8000 |
| Healthcheck | `/healthz` |
| Volume | `/root/.cache` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `WHISPER_AUTH_USERNAME` | `admin` |
| `WHISPER_AUTH_PASSWORD` | `${{secret(24)}}` |
| `ASR_MODEL` | `base` |
| `WHISPER_MAX_UPLOAD_MB` | `512` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `900` |
| `PORT` | `8000` |
| `TZ` | `UTC` |

## Notes

- Every variable has a value or a generator, so `railway deploy -t whisper-asr-webservice` works without a TTY.
- **The healthcheck path must be `/healthz`, not `/`.** Everything else is behind basic
  authentication and answers 401, which Railway treats as unhealthy. That one route is deliberately
  left open and returns only the word `ok`.
- **The healthcheck timeout is raised with a variable, not a template field.** A generated template
  carries `healthcheckPath` but no timeout, so the template sets
  `RAILWAY_HEALTHCHECK_TIMEOUT_SEC=900` instead. The first start downloads the model, about 140 MB
  for `base` over a link that is not always fast, and the health route answers 502 until it is
  loaded; the platform default of 300 seconds can fail the first deploy of a healthy service.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the value
  of `PORT`, defaulting to 8080. A service that serves the public domain perfectly still fails to
  deploy if nothing listens on `PORT`.
- Do not add `WHISPER_HOST`. The image pins the application to loopback and the wrapper refuses to
  start if that is overridden, because moving it would publish an unauthenticated endpoint.
- The volume must mount `/root/.cache`. Both the openai-whisper cache (`~/.cache/whisper`) and the
  Hugging Face cache used by the other engines live under it.
- The image is large, roughly eight gigabytes unpacked, because it carries a CPU build of PyTorch.
  The first deploy pulls it; later deploys of the same tag do not.
- There is no second service and nothing on the private network.
