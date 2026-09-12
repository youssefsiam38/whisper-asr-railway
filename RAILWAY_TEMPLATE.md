# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Whisper ASR Webservice |
| Code | `whisper-asr` |
| Template id | _filled in at publication_ |
| Deploy URL | https://railway.com/deploy/whisper-asr |
| Category | Other |
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
| Healthcheck timeout | 900 s |
| Volume | `/root/.cache` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `WHISPER_AUTH_USERNAME` | `admin` |
| `WHISPER_AUTH_PASSWORD` | `${{secret(24)}}` |
| `ASR_MODEL` | `base` |
| `PORT` | `8000` |
| `TZ` | `UTC` |

## Notes

- Every variable has a value or a generator, so `railway deploy -t whisper-asr` works without a TTY.
- **The healthcheck path must be `/healthz`, not `/`.** Everything else is behind basic
  authentication and answers 401, which Railway treats as unhealthy. That one route is deliberately
  left open and returns only the word `ok`.
- **The healthcheck timeout has to be generous.** The first start downloads the model: about 140 MB
  for `base` over a link that is not always fast. Until it is loaded the health route answers 502,
  and a short timeout fails the first deploy of an otherwise healthy service.
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
