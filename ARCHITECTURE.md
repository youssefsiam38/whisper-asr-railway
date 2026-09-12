# Architecture

## Service graph

One service, one volume. There is no database, no cache and no queue.

```
internet --> Railway edge (TLS) --> :PORT  Caddy  --> 127.0.0.1:9000  Whisper ASR Webservice
                                      |                                    |
                                      |                                    +-- /root/.cache (volume)
                                      +-- /healthz  open, proxied, body discarded
                                      +-- everything else  HTTP basic auth
```

## Why a wrapper image

Upstream is a FastAPI application with three routes and no notion of a user. From
`app/webservice.py`:

- `GET /` redirects to `/docs`
- `POST /asr`
- `POST /detect-language`

None of them consults a credential, and there is no setting that adds one. That is a reasonable
design for a component you run behind your own gateway, and an unreasonable one to expose directly.
Railway publishes a hostname as soon as the service deploys, so the options were to patch the
application or to put something in front of it.

Patching would mean maintaining a fork of a Python package against every upstream release. Fronting
it means the upstream image is used exactly as published, pinned by digest, and a version bump is a
one-line change with no code to re-review. The wrapper therefore adds a proxy and changes nothing
else.

## The front door

Caddy is copied in as a static binary from the official `caddy:2.10-alpine` image. It listens on the
platform's `PORT` and proxies to the webservice on loopback.

Two route groups:

- `/healthz` is open. It rewrites to the app's own `/openapi.json`, proxies that, and then throws
  the response away, answering `ok` with 200. While the model is still loading the app is not
  listening at all, so the proxy cannot connect and the route answers 502; if the app is listening
  but answering errors, it answers 503. The platform gets a probe that reflects whether the service
  can actually transcribe, and the public gets a status word with no API schema attached.
- Everything else requires HTTP basic authentication. The password is hashed with
  `caddy hash-password` at start-up; the plaintext never reaches the configuration file, and the
  file is written `0600` and validated with `caddy validate` before Caddy is allowed to read it.

A `request_body max_size` applies to the whole site, so an unauthenticated request cannot stream an
unbounded body into the process before the credential check rejects it.

## Boot sequence

1. Validate the environment. Names of missing or wrong variables are printed; values never are.
2. Create the model cache directory.
3. Hash the password and write the Caddy configuration, then validate it.
4. **Start Caddy.** The door is locked from the first instant, because the credential is already in
   the configuration Caddy is reading.
5. Start the webservice on loopback. Importing it loads the Whisper model, which downloads the
   weights on a cold volume.
6. A background loop logs readiness once `/openapi.json` answers. It gates nothing; `/healthz`
   already reports the true state.
7. Supervise both processes. If either exits, the container exits and the platform restarts it. A
   stop signal exits 0, so a deliberate stop is not reported as a crash.

Caddy starting first is a deliberate difference from the other templates in this family. Loading a
Whisper model takes minutes on a cold volume, and a locked door answering 503 tells the platform far
more than a refused connection does. It is safe here because there is no first-run account to claim:
the boundary is the proxy configuration, and it exists before the listener does.

## Ports

| Port | Listener | Reachable from |
|---|---|---|
| `PORT` (8000) | Caddy | the internet |
| 9000 | Whisper ASR Webservice | inside the container only |

`WHISPER_HOST` is pinned to `127.0.0.1` in the image and the entrypoint refuses to start if it is
changed, because moving the app off loopback would publish an unauthenticated endpoint next to the
authenticated one.

Railway runs its healthcheck against the value of `PORT`, not against the domain's target port. The
two must agree or a service that serves the public domain perfectly is still reported unhealthy.

## Health and readiness

`/healthz` is the healthcheck path. It is the only route that answers without credentials, and it
answers 502 while the model is loading, so the platform holds the deployment in progress rather than
cutting over to an instance that cannot yet transcribe anything.

The first start on an empty volume downloads the model: roughly 40 MB for `tiny`, 140 MB for `base`,
460 MB for `small`, and several gigabytes for the `large` family. The template sets a generous
healthcheck timeout for that reason. Subsequent starts read the model from the volume.
