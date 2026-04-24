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

## Upstream FreeSWITCH

Tracks FreeSWITCH 1.10.x. Upstream is MPL-2.0-licensed; the Dockerfile
builds against Debian packages at image-build time.

## License

MPL-2.0 (matches upstream). Contributions welcome — CLA signature
required via the CLA bot on each PR.
