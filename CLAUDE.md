# Todo App — Learning Project

## Goals

1. **Dev Container workflow** — build and run everything from within a VS Code dev container.
2. **Multi-container app** — React frontend + FastAPI backend, each in its own Docker image.
3. **Azure Container Apps** — deploy the stack to ACA using Azure CLI / Bicep.

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React 18, TypeScript, Vite |
| Backend | Python 3.12, FastAPI, uv, ruff |
| Local dev | Docker Compose |
| Cloud | Azure Container Apps, Azure Container Registry |
| Database (phase 3) | TBD — likely Azure PostgreSQL Flexible Server |

## Project Structure

```
/workspace/
├── CLAUDE.md
├── docker-compose.yml
├── frontend/
│   ├── Dockerfile
│   ├── package.json
│   ├── vite.config.ts
│   └── src/
├── backend/
│   ├── Dockerfile
│   ├── pyproject.toml   (uv-managed)
│   └── app/
└── infra/               (phase 3 — Bicep / AZ CLI scripts)
```

## Phases

### Phase 1 — Frontend with mock data ← CURRENT
- [ ] Scaffold Vite + React + TypeScript frontend
- [ ] Implement Todo UI (list, add, complete, delete) against mock/in-memory state
- [ ] Dockerize the frontend (multi-stage Nginx build)
- [ ] Verify `docker compose up` serves the app locally

### Phase 2 — FastAPI backend (in-memory)
- [ ] Scaffold FastAPI app managed by `uv`
- [ ] REST API: `GET /todos`, `POST /todos`, `PATCH /todos/{id}`, `DELETE /todos/{id}`
- [ ] Wire frontend to backend via environment-variable-configured base URL
- [ ] Add `ruff` linting to backend
- [ ] Update docker-compose to run both services

### Phase 3 — Azure deployment
- [ ] Push images to Azure Container Registry (ACR)
- [ ] Deploy to Azure Container Apps (ACA)
- [ ] Provision Azure PostgreSQL Flexible Server
- [ ] Migrate backend storage from in-memory to PostgreSQL (SQLModel / asyncpg)
- [ ] Wire secrets via ACA environment variables / Key Vault

## Current Status

**Phase 1 in progress.** Frontend skeleton being created.
