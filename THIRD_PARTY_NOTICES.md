# Third-party notices

This image redistributes software written by other people. Their licences are shipped inside it at
`/usr/share/licenses/whisper-asr-railway/` and vendored in `licenses/` here.

## Shipped inside the wrapper image

| Component | Licence | Source | Notice |
|---|---|---|---|
| Whisper ASR Webservice 1.10.0 | MIT | https://github.com/ahmetoner/whisper-asr-webservice | `licenses/WHISPER-ASR-LICENSE` |
| Caddy 2.10.2 | Apache-2.0 | https://github.com/caddyserver/caddy | `licenses/CADDY-LICENSE` |

The upstream image itself contains further components, among them OpenAI Whisper (MIT),
faster-whisper (MIT), WhisperX (BSD-2-Clause), PyTorch (BSD-3-Clause), FastAPI (MIT), Uvicorn
(BSD-3-Clause), FFmpeg (LGPL-2.1 or later as built by upstream) and Swagger UI (Apache-2.0). Their
notices travel in the layers upstream publishes; this wrapper does not repackage or relink any of
them.

Model weights are not shipped. They are downloaded at runtime from OpenAI's CDN or from Hugging Face
and are covered by their own terms.

## Licence obligations

Both vendored licences are permissive and require only that the notice accompanies the software.
Copying them into the image satisfies that for anyone who pulls the image without reading this
repository.

## Trademarks and artwork

"Whisper" and "OpenAI" are marks of OpenAI. The upstream project and this template are not
affiliated with or endorsed by OpenAI, nor by the Whisper ASR Webservice authors. The template icon
in `assets/` was made for this repository and is not an upstream logo.

## This repository

The wrapper, its entrypoint, its tests and its documentation are MIT licensed. See `LICENSE`.
