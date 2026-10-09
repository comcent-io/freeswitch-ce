# freeswitch-ce

FreeSWITCH configs, scripts, and Dockerfile tailored for Comcent Community
Edition. Layered on top of upstream FreeSWITCH; no core FreeSWITCH code
changes — only config and Lua scripts in `etc/` and `scripts/`.

## Build

```bash
docker build -t ghcr.io/comcent-io/freeswitch-ce:latest .
docker compose up   # for local testing
```

## How this plugs into comcent-ce

comcent-ce's Go SBC handles SIP signaling; this image handles media. The
main comcent-ce `docker-compose.yaml` references `ghcr.io/comcent-io/
freeswitch-ce:TAG` — you don't normally clone this repo unless you're
customizing the dialplan or adding modules.

## Releasing

Every push to `main` publishes the image as `:main` and an immutable
`:sha-<7>`. It never moves `:latest` or a version tag.

A release is made by hand, after the `:sha-<7>` build has been tested with
comcent-ce (calls in and out, audio both ways, hang-up from either end, a
recording uploaded):

1. Actions → **Release** → *Run workflow*, with `version` `vYYYY.MM.DD` for
   today (add `.1`, `.2` for another release the same day) and `sha` the
   commit you tested (blank means current `main`). It checks the
   `:sha-<7>` image exists, tags it `:<version>` and `:latest`, tags the
   commit and creates the GitHub Release. Never create a Release any other
   way: only this workflow gives the image its version tag.
2. In comcent-ce, open a PR pinning `freeswitch-ce:<version>` (see its
   `RELEASING.md`). Installs get it with comcent-ce's next release.

## Upstream FreeSWITCH

Tracks FreeSWITCH 1.10.x. Upstream is MPL-2.0-licensed; the Dockerfile
builds against Debian packages at image-build time.

## License

MPL-2.0 (matches upstream). Contributions welcome — CLA signature
required via the CLA bot on each PR.
