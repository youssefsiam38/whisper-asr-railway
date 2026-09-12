# syntax=docker/dockerfile:1
#
# whisper-asr-railway: thin wrapper around the official Whisper ASR Webservice image.
#
# Upstream ships no authentication at all. app/webservice.py registers exactly three routes -- `/`,
# `/asr` and `/detect-language` -- and none of them consults a credential, because the project is
# designed to sit on a private network behind something else. Railway gives every service a public
# URL, so deployed as-is it becomes an open speech-to-text endpoint that anyone who finds the
# hostname can feed audio to, at the deployer's expense. This wrapper puts Caddy in front with HTTP
# basic authentication and binds the webservice to loopback. Application code is unchanged.
#
# Both images are pinned by tag AND digest. Update the image and version args together.
ARG CADDY_IMAGE=docker.io/library/caddy:2.10-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
ARG WHISPER_IMAGE=docker.io/onerahmet/openai-whisper-asr-webservice:v1.10.0@sha256:0616c3d5fc6924e9d59aa8a7a3a944fbe8f3a5d701e5fc1fa2ce5b933dfecb73

FROM ${CADDY_IMAGE} AS caddy

FROM ${WHISPER_IMAGE}

ARG WHISPER_VERSION=1.10.0
ARG CADDY_VERSION=2.10.2
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root

# Caddy ships as a static Go binary, so the alpine-built one runs on this Debian base unchanged.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY licenses/ /usr/share/licenses/whisper-asr-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/whisper-asr-railway-entrypoint
RUN caddy version && install -d /etc/whisper-asr-railway

# The webservice listens on loopback only; Caddy owns the public port. ASR_MODEL_PATH and the
# Hugging Face cache both live under /root/.cache, which is where the Railway volume mounts, so a
# downloaded model survives a redeploy instead of being fetched again on every cold start.
ENV WHISPER_HOST=127.0.0.1 \
    WHISPER_INTERNAL_PORT=9000 \
    WHISPER_AUTH_USERNAME=admin \
    ASR_ENGINE=openai_whisper \
    ASR_MODEL=base \
    HF_HOME=/root/.cache/huggingface

LABEL org.opencontainers.image.title="whisper-asr-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Whisper ASR Webservice, a self-hosted speech-to-text API. Adds authentication. Not affiliated with the upstream project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/whisper-asr-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/whisper-asr-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/whisper-asr-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/onerahmet/openai-whisper-asr-webservice:v${WHISPER_VERSION}" \
      io.whisper-asr-railway.upstream.version="${WHISPER_VERSION}" \
      io.whisper-asr-railway.caddy.version="${CADDY_VERSION}"

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/whisper-asr-railway-entrypoint"]
