# Marketplace audit

Checked 2026-09-12 against Railway's template search.

## Gap

`templateSearch` returns no template named after Whisper ASR Webservice. The speech category is not
empty, though, and it is worth being precise about what is already there:

| Existing template | Deploys | What it is |
|---|---:|---|
| Faster Whisper | 19 | A combined speech-to-text and text-to-speech service, OpenAI-shaped API |
| Speaches | 12 | An OpenAI-compatible STT and TTS server, a different project |
| Whisper STT API | 1 | An OpenAI-compatible endpoint with a model baked into the image |
| Speech (Whisper + Kokoro) | 0 | Two models behind one endpoint |
| Kokoro, KittenTTS, Pocket TTS, FlowSpeech | 0-10 | Text to speech, the opposite direction |

Every one of those exposes an OpenAI-compatible `/v1/audio/transcriptions` surface. Whisper ASR
Webservice is a different product with a different API: `POST /asr` with an `output` parameter that
returns plain text, JSON with word-level segments, SRT, WebVTT or TSV, plus `POST /detect-language`.
Subtitle generation is the use case those other templates do not serve, and it is what this project
is most used for.

It is also the most widely deployed of the group outside Railway, with published multi-architecture
CPU images on every release and a stable API since 2022, so pinning it is low risk.

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

AI/ML. Railway added that category after the earlier templates in this family were published, and it
is the right home for a speech-recognition service.
