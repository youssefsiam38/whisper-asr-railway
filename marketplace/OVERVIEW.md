# Deploy and Host Whisper ASR Webservice on Railway

Whisper ASR Webservice turns recorded speech into text. Send it an audio or video file over HTTP and
it returns a transcript, subtitles in SRT or WebVTT, or just the language it detected. It runs
OpenAI's Whisper models on your own instance, so nothing is sent to a third-party transcription API
and there is no per-minute bill. This is a community-maintained template; it is not affiliated with
the upstream project.

## About Hosting Whisper ASR Webservice

Hosting it is simple in shape and has one sharp edge. The shape is a single Python service with no
database, no cache and no queue: one container, one volume holding the downloaded model. The sharp
edge is that the application has no authentication at all. It defines three routes and none of them
checks a credential, because the project is designed to sit on a private network behind something
else. On a platform that hands every service a public address, that assumption stops being true the
moment the deploy finishes, and an open transcription endpoint is a bill waiting to happen.

This template puts a password in front of the application and binds the application itself to
loopback, so the only way in is through the front door. The password is generated for you. One
route stays open, the health route, and it returns a single status word so the platform can tell
whether the model has finished loading.

## Why Deploy Whisper ASR Webservice on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Whisper ASR Webservice on Railway, you are one step closer to supporting a complete
full-stack application with minimal burden. Host your servers, databases, AI agents, and more on
Railway.

Concretely, this template generates the password, configures the front door, attaches the volume the
model is cached in, pins the listening port to the generated domain, caps upload sizes, and points
the healthcheck at the one route that stays open, so you get a working and protected speech-to-text
API with nothing to fill in.

## Common Use Cases

- Transcribe interviews, meetings and voice notes without sending the audio to a third party.
- Generate subtitles for a video library, in SRT or WebVTT, in one request per file.
- Give an application a private speech-to-text endpoint it can call over HTTP.
- Detect what language a recording is in before routing it somewhere else.

## Dependencies for Whisper ASR Webservice Hosting

- A persistent volume for the downloaded model, so a redeploy does not fetch it again.
- Enough memory for the chosen model. The default is the `base` model, which is modest; the `large`
  family needs several gigabytes and is slow without a GPU.
- Nothing else. No external database, cache or queue.

### Deployment Dependencies

- Whisper ASR Webservice upstream project: https://github.com/ahmetoner/whisper-asr-webservice
- OpenAI Whisper, the model family it runs: https://github.com/openai/whisper
- Caddy, used as the authenticating front door: https://caddyserver.com
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/whisper-asr-railway
- Published image: `ghcr.io/youssefsiam38/whisper-asr-railway`
- The upstream project is MIT licensed and Caddy is Apache-2.0; both are permissive.

### Implementation Details

The wrapper adds no application code. It validates the configuration and refuses to start on a
missing or short password, an unknown model or engine, WhisperX without a Hugging Face token, a port
collision, or an attempt to move the application off loopback. It hashes the password into a proxy
configuration that it validates before use, then opens the public port and starts the application
behind it. The health route proxies the application's own schema endpoint to decide what to report
and discards the response, so it reflects the real state without publishing anything. Both processes
are supervised, so if either stops the container stops and the platform restarts it.
