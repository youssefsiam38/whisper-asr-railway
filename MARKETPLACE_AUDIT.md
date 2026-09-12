# Marketplace audit

Checked 2026-09-12 against Railway's template search.

## Gap

`templateSearch` returns no template named after Whisper ASR Webservice, and none of the loose
matches is a speech-to-text service. The adjacent AI templates that do exist solve different
problems:

| Existing template | What it is | Why it does not cover this |
|---|---|---|
| Speaches | An OpenAI-compatible speech server | A different project with a different API surface. |
| Kokoro | Text to speech | The opposite direction. |
| LibreTranslate | Text translation | No audio at all. |
| Ollama, LocalAI | LLM inference servers | They do not transcribe audio. |

There is no self-hosted transcription API on the marketplace.

## Why Whisper ASR Webservice

- MIT licensed, so redistributing a wrapper image is unencumbered.
- 3,335 stars and a release nine days before this audit, so it is maintained rather than merely
  popular.
- Multi-architecture CPU images are published by upstream on every release, and they are the
  supported way to run it.
- It is a single container with no database, which is the shape that deploys well.
- The demand is real and recurring: transcription is the one AI workload people most often want to
  keep off a third-party API, because the input is a recording of a meeting, a patient, a source or
  a family member.

## Why it needs a template rather than a raw image

Deploying `onerahmet/openai-whisper-asr-webservice` directly to Railway produces a working service
that anyone on the internet can use. That is not a misconfiguration on the deployer's part; the
application has no authentication to switch on. Upstream's documentation puts it behind a private
network, which a public platform does not have.

The template also settles four things that are easy to get wrong and produce confusing failures:

1. **The port.** Railway probes its healthcheck against `PORT`; upstream listens on 9000 and ignores
   that variable entirely.
2. **The health route.** There is no health endpoint in the application. Probing `/` gives a
   redirect, and once authentication is added, a 401.
3. **The model cache.** Without a volume the model is downloaded again on every deploy, which turns
   a redeploy into a multi-minute outage.
4. **Cold start.** The model loads at import time, so the service is unreachable for minutes on a
   first deploy. Without a health route that reports honestly, the platform cuts over to an instance
   that cannot answer.

## Category

Other. Railway has no AI or machine-learning category; the existing inference and AI templates sit
under Other as well.
