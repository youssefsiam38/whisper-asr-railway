# Whisper ASR Webservice on Railway

A community Railway template for [Whisper ASR Webservice][upstream], a self-hosted speech-to-text
API built on OpenAI's Whisper. Upload audio, get back a transcript, subtitles or a detected
language. It is not affiliated with the upstream project.

Upstream ships **no authentication**. `app/webservice.py` registers exactly three routes, `/`,
`/asr` and `/detect-language`, and none of them looks at a credential, because the project assumes
it is sitting on a private network. Railway hands every service a public hostname the moment it
deploys, which turns that assumption into an open transcription service running on your account.

This repository publishes a thin wrapper image that restores the boundary: Caddy fronts the app with
HTTP basic authentication, and the app itself only listens on loopback. No application code is
changed and no route is rewritten, so anything that works against the upstream API works here, with
credentials attached.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/whisper-asr-webservice)

## What you get

- The official upstream image, pinned by tag and digest, with Caddy in front.
- A password you never have to invent: the template generates one.
- One open route, `/healthz`, which exists so the platform can probe the service. It returns the
  word `ok` and nothing else, and it reports the app's real state rather than a hard-coded 200.
- A persistent volume for the Whisper model, so a redeploy does not download it again.
- An upload size cap, so a public endpoint cannot be filled by one request.
- Fail-fast validation: the container refuses to start with a missing password, a short password, an
  unknown model, an unknown engine, WhisperX without a Hugging Face token, a port collision, or an
  attempt to move the app off loopback.

## First run

1. Deploy the template. Railway generates `WHISPER_AUTH_PASSWORD` for you.
2. Copy that value out of the service variables. It is the password for user `admin`.
3. Wait for the first start to finish. It downloads the Whisper model, which takes a few minutes on
   `base` and considerably longer on the larger ones. `/healthz` answers `502` until it is done.
4. Transcribe something:

```bash
curl -u admin:YOUR_PASSWORD \
  -F 'audio_file=@meeting.mp3' \
  'https://YOUR-DOMAIN/asr?output=json'
```

The interactive API documentation is at `/docs`, behind the same credentials.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `WHISPER_AUTH_PASSWORD` | none, required | Basic-auth password. At least 12 characters. |
| `WHISPER_AUTH_USERNAME` | `admin` | Basic-auth user. |
| `WHISPER_ALLOW_PUBLIC` | `false` | `true` disables authentication entirely. Read `SECURITY.md` first. |
| `ASR_MODEL` | `base` | Whisper model. `tiny`, `base` and `small` are the practical CPU choices. |
| `ASR_ENGINE` | `openai_whisper` | `openai_whisper`, `faster_whisper` or `whisperx`. |
| `HF_TOKEN` | none | Required only by `whisperx`, for its diarization model. |
| `WHISPER_MAX_UPLOAD_MB` | `512` | Largest accepted upload. |
| `WHISPER_INTERNAL_PORT` | `9000` | Loopback port the app listens on. Change only on a collision. |
| `PORT` | `8000` | Public port. Railway sets this and probes its healthcheck against it. |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `900` | How long Railway waits for the health route on a first deploy. Raise it further for a large model. |

`ASR_QUANTIZATION`, `MODEL_IDLE_TIMEOUT`, `SAMPLE_RATE` and the subtitle options are passed through
to upstream untouched; see its documentation.

## Persistent paths

| Path | Holds |
|---|---|
| `/root/.cache` | Downloaded Whisper models, and the Hugging Face cache for the other engines. |

Nothing else survives a restart. This service stores no transcripts: audio goes in, text comes back,
and neither is written to disk.

## Local development

```bash
docker compose build
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

The local stack uses the `tiny` model to keep the test run short. `tests/railway-smoke.sh
https://your-domain` checks a deployed instance; set `CREDS_FILE` to a file holding
`username:password` to exercise the authenticated paths too.

## Documentation

| File | Covers |
|---|---|
| `ARCHITECTURE.md` | Service graph, the front door, boot sequence, ports, health. |
| `SECURITY.md` | What is exposed, what is not, and how to opt out safely. |
| `UPSTREAM.md` | Provenance, what the wrapper changes, how to bump the version. |
| `MAINTENANCE.md` | Release process, what to watch, rollback. |
| `THIRD_PARTY_NOTICES.md` | Licences shipped in the image. |
| `MARKETPLACE_AUDIT.md` | Why this template exists. |
| `RAILWAY_TEMPLATE.md` | The exact published template configuration. |

## Licence

The wrapper is MIT. Whisper ASR Webservice is MIT and Caddy is Apache-2.0; both licences travel
inside the image at `/usr/share/licenses/whisper-asr-railway/`.

[upstream]: https://github.com/ahmetoner/whisper-asr-webservice
