# CLAUDE.md — matter-hub

## Project Overview

**matter-hub** is a local-first orchestration platform for indexing ChatGPT history, cataloging projects, orchestrating agents, and extracting narrative universes from dispersed sources. All processing runs on localhost — no external APIs except optional Gmail integration.

## Tech Stack

- **Python 3** — primary language
- **FastAPI + Uvicorn** — web servers
- **SQLite** — databases (FTS5 for full-text search, WAL journaling)
- **Jinja2** — HTML templates
- **Ollama** — local embeddings via `nomic-embed-text` model (runs on `http://127.0.0.1:11434`)
- **BabylonJS** — 3D "Cocoon" overlay (loaded from CDN)

## Repository Structure

```
matter_hub/
├── hub/                          # Core application
│   ├── hub_server.py            # Main FastAPI app (port 8900) — Projects/Search/Canon/Ledger
│   ├── ledger_server.py         # Action ledger UI + API (port 8899)
│   ├── search.py                # Hybrid search engine (FTS + semantic)
│   ├── semantic_index.py        # Embedding indexer (Ollama)
│   ├── semantic_search.py       # Semantic search CLI
│   ├── extract_universe.py      # Universe fragment extractor
│   ├── action_log.py            # Ledger context manager library (log_event)
│   ├── actions_query.py         # Ledger query CLI
│   ├── actions_export_md.py     # Export ledger to markdown
│   ├── run_logged.py            # Command wrapper with ledger logging
│   ├── ollama_smoke.py          # Ollama connectivity smoke test
│   ├── cocoon.js                # BabylonJS 3D overlay
│   ├── cocoon.css / hub_shell.css  # Styling
│   ├── project_tags.json        # Pattern-based project/universe tagging rules
│   ├── templates/               # Jinja2 HTML templates
│   │   ├── base.html            # Layout shell + Cocoon + theme toggle
│   │   ├── projects.html        # Projects browser
│   │   ├── search.html          # Search UI
│   │   ├── canon.html           # Canon bundle browser
│   │   ├── canon_bundle.html    # Bundle listing
│   │   └── canon_file.html      # File viewer
│   ├── _logs/                   # Runtime logs (gitignored)
│   └── _canon/                  # Universe extraction outputs
├── registry/
│   ├── build_registry.py        # Project scanner and discovery
│   ├── projects.json            # Indexed projects (~100 entries)
│   └── projects-scan.raw.json   # Raw scan output
├── connectors/
│   └── google/
│       ├── gmail_index_headers.py  # Gmail OAuth + header indexing
│       └── requirements.txt
└── .gitignore
```

## Running the Application

```bash
python hub/hub_server.py          # Main UI server on port 8900
python hub/ledger_server.py       # Action ledger on port 8899
python hub/search.py              # CLI search tool
python hub/semantic_index.py      # Build embedding index
python hub/extract_universe.py    # Extract universe fragments
python registry/build_registry.py # Rebuild project registry
```

No formal build system (no npm, no Makefile). Scripts are run directly with Python.

## Databases

All `.sqlite` files are gitignored. No ORM — raw `sqlite3` with context managers.

| Database | Purpose |
|---|---|
| `actions.sqlite` | Action ledger — event log for all agent/script actions |
| `chatgpt.sqlite` | ChatGPT messages with FTS5 index |
| `semantic.sqlite` | Embeddings (binary float32 LE blobs) |
| `gmail.sqlite` | Gmail headers (future) |

Schema migration uses an `ensure_db()` + `_has_column()` pattern — columns are added as needed without formal migration files.

## Key Patterns and Conventions

### Action Logging

Every significant operation wraps work in a `log_event()` context manager from `action_log.py`:

```python
from action_log import log_event

with log_event('semantic_index', params={...}, message='...', tags=['tag']) as ev:
    # do work
    ev.ok(extra={...})    # on success
    ev.fail(error=...)    # on failure
```

### Hybrid Search

Search merges FTS (BM25 scores normalized to 0–1) with semantic cosine similarity. Best score wins per document. Project tagging uses substring pattern matching from `project_tags.json`.

### Binary Vector Storage

Embedding vectors are stored as binary blobs (`struct.pack` float32 LE) in SQLite for memory efficiency.

### Auto-schema Migration

Database schemas evolve via `ensure_db()` functions that create tables/columns if missing. No separate migration files.

## Testing

No formal test framework. The only test is `hub/ollama_smoke.py` which validates Ollama connectivity. Run it with:

```bash
python hub/ollama_smoke.py
```

## Dependencies

**Python** (install manually or via venv):
- `fastapi`, `uvicorn`, `jinja2`
- `sqlite3` (stdlib)
- For Gmail connector: `google-api-python-client`, `google-auth-oauthlib` (see `connectors/google/requirements.txt`)

**External services:**
- **Ollama** must be running locally on port 11434 with model `nomic-embed-text:latest` pulled

## Git Conventions

- Commit messages follow the pattern: `Component: short description of change`
- Examples: `Cocoon: add environment reflections`, `Hub: listen on 0.0.0.0`, `Search v2: filters...`
- `.gitignore` excludes: `__pycache__/`, `*.pyc`, `.venv/`, `node_modules/`, `*.sqlite*`, `hub/_data/`, `hub/_logs/`

## Architecture Notes

- **Local-first / privacy-centric** — no cloud dependencies for core functionality
- **Port separation** — Ledger (8899) and Hub (8900) are separate FastAPI apps
- **Pattern-based tagging** — project/universe detection via substring patterns in `project_tags.json`
- **No CI/CD** — no GitHub Actions or equivalent configured
- **Servers bind to 0.0.0.0** for local network access
