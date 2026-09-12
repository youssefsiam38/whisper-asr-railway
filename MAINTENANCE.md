# Maintenance

## Release process

1. Make the change on a branch. `tests/static.sh` runs on every push and pull request; the full
   suite runs in the `test` workflow.
2. Run locally:
   ```bash
   docker compose build --pull
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. Tag `vX.Y.Z`. The `publish-image` workflow builds an amd64 candidate, runs the smoke and
   persistence suites against that exact image, and only then pushes the multi-arch image to GHCR
   as `X.Y.Z`, `X.Y` and `latest`.
4. Update the Railway template to the new tag. `RAILWAY_TEMPLATE.md` records the exact
   configuration; the template pins a version tag, never a digest, because the template generator
   rejects `@sha256:` references.
5. Deploy the updated template into a scratch project and run
   `tests/railway-smoke.sh https://domain` against it before leaving it published.

The wrapper version and the upstream version move independently. A wrapper release that only
changes documentation still gets a new tag, so the template always points at something immutable.

## What to watch

| Source | Why |
|---|---|
| https://github.com/ahmetoner/whisper-asr-webservice/releases | New versions, new environment variables, engine changes. |
| That repository's `app/webservice.py` | **If upstream ever adds routes, they land behind basic auth automatically, but a new open route would not.** Re-read the route table on every bump. |
| https://github.com/caddyserver/caddy/releases | Security fixes in the front door. |
| Railway's healthcheck behaviour | The probe runs against `PORT`; a platform change there breaks every template in this family at once. |

## Breaking-change checklist

Before bumping the upstream digest, confirm:

- [ ] The entrypoint binary is still `whisper-asr-webservice` and still accepts `--host` and
      `--port`. The wrapper invokes it directly.
- [ ] `/openapi.json` still exists and still answers 200. The health route depends on it.
- [ ] `ASR_MODEL_PATH` still defaults under `~/.cache`, or the volume mount path changes with it.
- [ ] The model catalogue in the entrypoint still matches what openai-whisper publishes. A model
      added upstream but missing from that list would be rejected by the wrapper's validation.
- [ ] The image still runs as root, or the entrypoint grows a chown and a privilege drop.
- [ ] `.info.version` in the served OpenAPI document matches the new version, since two tests assert
      on it.

## Rolling back

Republish the template with the previous wrapper tag. The images are immutable and the model cache
on the volume is forward and backward compatible, so a rollback is a tag change and a redeploy with
no data migration.

## If this repository is abandoned

The image is a thin wrapper: the Dockerfile, the entrypoint and the tests are the whole of it. Fork
it, change the `org.opencontainers.image.source` label and the GHCR path, and publish your own
template. Nothing in the design depends on this account.
