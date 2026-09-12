# Upstream provenance

## Whisper ASR Webservice

| | |
|---|---|
| Project | https://github.com/ahmetoner/whisper-asr-webservice |
| Licence | MIT (`LICENCE`, Ahmet Oner & Besim Alibegovic, 2022) |
| Version pinned | 1.10.0, released 2026-08-09 |
| Image | `docker.io/onerahmet/openai-whisper-asr-webservice:v1.10.0` |
| Digest | `sha256:0616c3d5fc6924e9d59aa8a7a3a944fbe8f3a5d701e5fc1fa2ce5b933dfecb73` |
| Architectures | linux/amd64, linux/arm64 |

The CPU image is used. Upstream also publishes a `-gpu` tag, which is roughly ten gigabytes and
needs CUDA hardware; Railway does not sell a GPU on its standard plans, so a static check in
`tests/static.sh` fails if a `-gpu` tag is ever pinned here.

The application bundles OpenAI Whisper, faster-whisper and WhisperX, and selects between them with
`ASR_ENGINE`. Model weights are not in the image; they are downloaded on first use.

## Caddy

| | |
|---|---|
| Project | https://caddyserver.com |
| Licence | Apache-2.0 |
| Version pinned | 2.10.2 via `caddy:2.10-alpine` |
| Digest | `sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d` |

Only the binary is copied out of that image. Caddy is a static Go binary, so the Alpine build runs
unchanged on the Debian-based upstream image.

## What this repository changes

It adds four things and removes none:

1. The Caddy binary at `/usr/local/bin/caddy`.
2. `scripts/entrypoint.sh` as the image entrypoint, replacing the upstream `whisper-asr-webservice`
   entrypoint, which it still invokes.
3. Environment defaults that pin the application to loopback (`WHISPER_HOST`,
   `WHISPER_INTERNAL_PORT`) and set `HF_HOME` inside the volume.
4. The two upstream licences at `/usr/share/licenses/whisper-asr-railway/`.

No Python file is patched, no route is added or rewritten, and no dependency is changed. The
application cannot tell it is behind a proxy except that its listener is on loopback.

## Licence obligations

Both upstream licences are permissive and both require their notice to travel with the software.
They are vendored in `licenses/` and copied into the image. `THIRD_PARTY_NOTICES.md` records what is
shipped and why.

The wrapper itself is MIT. Redistributing the wrapper image redistributes the upstream image, which
is why the notices are inside it rather than only in this repository.

## Bumping the upstream version

1. Read the upstream release notes and `CHANGELOG.md` for new or renamed environment variables.
2. Resolve the new digest:
   `docker buildx imagetools inspect docker.io/onerahmet/openai-whisper-asr-webservice:vX.Y.Z`
3. Update `WHISPER_IMAGE` and `WHISPER_VERSION` in the Dockerfile and the assertion in
   `tests/static.sh`, which pins the tag string.
4. Update the version assertions in `tests/smoke.sh` and `tests/railway-smoke.sh`, which check
   `.info.version` from the served OpenAPI document.
5. Run the full suite locally, then tag a release. CI rebuilds, retests against the candidate image
   and pushes.
