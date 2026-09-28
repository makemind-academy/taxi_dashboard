# taxi-dashboard

The door frame starts the meter, speed frames become the fare, arriving puts payment due; the passenger pays with one press.

Article: [taxi-one-dashboard](https://makemind.dev/en/field/taxi-one-dashboard)

## What is here

- `dashboard_server/` — Dart MCP server (`mcp_server` from pub.dev). It holds the data and the tools and serves the app's pages as `ui://` resources.
- `vehicle_bus/` — C program standing in for the hardware, built by `verify.sh`.
- `captures/` — screenshots taken from AppPlayer by `verify.py`.
- `verify.py`, `verify.sh` — the check.

## Open it in AppPlayer

Add a server app with command `dart`, arguments `run bin/server.dart`, working directory `dashboard_server/`. The server serves its pages; the player draws them.

## Verify

```bash
bash verify.sh
```

Needs AppPlayer with the debug MCP on (see `tools/README.md`). The script builds what needs building, drives the player through the screens above, asserts the claim at the top of this file, and writes `captures/`.
