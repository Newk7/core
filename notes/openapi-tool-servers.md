# OpenAPI Tool Servers for OpenWebUI

## Overview

We run multiple OpenAPI tool servers from [open-webui/openapi-servers](https://github.com/open-webui/openapi-servers) alongside OpenWebUI and Open Terminal. All services run in Docker.

## Port Allocation

| Port | Service | Container Name |
|------|---------|---------------|
| 3000 | OpenWebUI | open-webui |
| 8000 | Open Terminal | open-terminal |
| 8081 | Filesystem | openapi-servers-filesystem-server-1 |
| 8082 | Memory | openapi-servers-memory-server-1 |
| 8083 | Time | openapi-servers-time-server-1 |
| 8084 | Weather | openapi-servers-weather-server-1 |
| 8085 | Get User Info | openapi-servers-get-user-info-server-1 |
| 8086 | Slack (disabled) | — |
| 8087 | Summarizer | openapi-servers-summarizer-server-1 |

Next available port: **8088**

## Compose File

Located at `/Users/kevin/work/openapi-servers/compose.yaml`. All servers build from `./servers/<name>` and map unique host ports to container port 8000.

```bash
cd ~/work/openapi-servers
docker compose up -d                    # start all
docker compose up -d filesystem-server  # start one
docker compose down                     # stop all
```

## Docker Networking

OpenWebUI runs on the default `bridge` network. The tool servers run on `openapi-servers_default`. For OpenWebUI to reach the tool servers, it must be connected to both:

```bash
docker network connect openapi-servers_default open-webui
```

This command does **not** survive container recreation. If you recreate the open-webui container, re-run it.

## Registering in OpenWebUI

1. Go to **Admin Settings → Tools** (or **Functions & Tools**)
2. Add each server using the **container name and internal port 8000** (not host port):

| Server | URL |
|--------|-----|
| Filesystem | `http://openapi-servers-filesystem-server-1:8000` |
| Memory | `http://openapi-servers-memory-server-1:8000` |
| Time | `http://openapi-servers-time-server-1:8000` |
| Weather | `http://openapi-servers-weather-server-1:8000` |
| Get User Info | `http://openapi-servers-get-user-info-server-1:8000` |

3. Leave API key **blank** — these servers don't require authentication.

## Adding New Servers

1. Edit `~/work/openapi-servers/compose.yaml`
2. Add a new service with the next port (8088+)
3. `docker compose up -d`
4. Register in OpenWebUI using `http://<container-name>:8000`
5. Update the port table above

## Notes

- **Slack server** requires `SLACK_BOT_TOKEN` env var — commented out in compose until configured.
- **Summarizer** requires an Ollama instance at `host.docker.internal:11434` with the `llama3` model.
- Open Terminal repo: `~/work/open-terminal`
- OpenAPI Servers repo: `~/work/openapi-servers`
