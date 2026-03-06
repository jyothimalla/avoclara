# Avoclara Backend

FastAPI backend scaffold for Avoclara.

## Features
- JWT auth (register/login/me)
- Task CRUD per user
- SQLite by default (easy local start)
- Docker + docker-compose

## Quick start (local)
1. Create venv and install deps:
   - `python3 -m venv .venv`
   - `source .venv/bin/activate`
   - `pip install -r requirements.txt`
2. Create env:
   - `cp .env.example .env`
3. Run API:
   - `uvicorn app.main:app --reload`
4. Open docs:
   - `http://127.0.0.1:8000/docs`

## API base
- `/api/v1`

## Endpoints
- `GET /api/v1/health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- `GET /api/v1/tasks`
- `POST /api/v1/tasks`
- `PATCH /api/v1/tasks/{task_id}`
- `DELETE /api/v1/tasks/{task_id}`

## Docker
- `cp .env.example .env`
- `docker compose up --build`
