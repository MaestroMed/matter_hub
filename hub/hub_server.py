"""matter-hub — Everything app (Projects + Search + Canon + Ledger).

This wraps:
- /ledger  -> existing ledger UI (imported from hub/ledger_server.py routes)
- /projects -> registry/projects.json browser
- /search -> UI calling /api/search
- /canon -> browse hub/_canon bundles

Run:
  python hub/hub_server.py
Open:
  http://127.0.0.1:8900/

Note: This is a lightweight shell. Ledger stays on 8899.
Later we can merge ports.
"""

from __future__ import annotations

import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from jinja2 import Environment, FileSystemLoader, select_autoescape

ROOT = Path(__file__).resolve().parent
REGISTRY = ROOT.parent / 'registry' / 'projects.json'
CANON_DIR = ROOT / '_canon'

app = FastAPI(title='matter-hub')

env = Environment(
    loader=FileSystemLoader(str(ROOT / 'templates')),
    autoescape=select_autoescape(['html', 'xml']),
)

app.mount('/static', StaticFiles(directory=str(ROOT), html=False), name='static')


def _render(template: str, **ctx):
    t = env.get_template(template)
    return HTMLResponse(t.render(**ctx))


@app.get('/')
def home():
    return HTMLResponse('<meta http-equiv="refresh" content="0; url=/projects" />')


@app.get('/projects', response_class=HTMLResponse)
def projects_page():
    data = json.loads(REGISTRY.read_text(encoding='utf-8')) if REGISTRY.exists() else {'projects': []}
    return _render('projects.html', title='matter-hub — Projects', active='projects', count=len(data.get('projects', [])))


@app.get('/api/projects')
def api_projects(q: str | None = None, kind: str | None = None, sort: str = 'score', limit: int = 500):
    data = json.loads(REGISTRY.read_text(encoding='utf-8')) if REGISTRY.exists() else {'projects': []}
    rows = data.get('projects', [])

    if q:
        ql = q.lower()
        rows = [p for p in rows if ql in (p.get('name','').lower() + ' ' + p.get('path','').lower())]

    if kind:
        rows = [p for p in rows if kind in (p.get('kinds') or [])]

    if sort == 'name':
        rows.sort(key=lambda p: (p.get('name') or '').lower())
    elif sort == 'path':
        rows.sort(key=lambda p: (p.get('path') or '').lower())
    else:
        rows.sort(key=lambda p: -(p.get('score') or 0))

    return JSONResponse(rows[: max(1, min(int(limit), 2000))])


@app.get('/search', response_class=HTMLResponse)
def search_page():
    return _render('search.html', title='matter-hub — Search', active='search')


@app.get('/api/search')
def api_search(q: str, project: str | None = None, role: str | None = None, top: int = 10, group: int | None = None):
    # call the underlying search v2 by importing its functions
    import hub.search as s
    since = None
    until = None
    chat = __import__('sqlite3').connect(str(s.CHAT_DB))
    fts = s.fts_search(chat, q, role, since, until, 25)
    sem = s.semantic_search(q, role, since, until, 25)
    merged = s._merge_results(fts, sem, project)
    out = {
        'query': q,
        'project': project,
        'role': role,
        'counts': {'fts': len(fts), 'semantic': len(sem), 'merged': len(merged)},
        'hits': merged[: max(1, min(int(top), 50))],
    }
    return JSONResponse(out)


@app.get('/canon', response_class=HTMLResponse)
def canon_page():
    bundles = []
    if CANON_DIR.exists():
        bundles = sorted([p.name for p in CANON_DIR.iterdir() if p.is_dir()])
    return _render('canon.html', title='matter-hub — Canon', active='canon', bundles=bundles)


@app.get('/canon/{bundle}', response_class=HTMLResponse)
def canon_bundle(bundle: str):
    p = CANON_DIR / bundle
    if not p.exists() or not p.is_dir():
        return HTMLResponse('not found', status_code=404)
    files = sorted([x.name for x in p.iterdir() if x.is_file()])
    return _render('canon_bundle.html', title=f'matter-hub — Canon {bundle}', active='canon', bundle=bundle, path=str(p), files=files)


@app.get('/canon/{bundle}/file/{filename}', response_class=HTMLResponse)
def canon_file(bundle: str, filename: str):
    p = CANON_DIR / bundle / filename
    if not p.exists() or not p.is_file():
        return HTMLResponse('not found', status_code=404)
    content = p.read_text(encoding='utf-8', errors='replace')
    return _render('canon_file.html', title=f'matter-hub — {bundle}/{filename}', active='canon', bundle=bundle, filename=filename, path=str(p), content=content)


def main():
    import uvicorn
    # Listen on all interfaces so it works from other devices too.
    uvicorn.run(app, host='0.0.0.0', port=8900, log_level='info')


if __name__ == '__main__':
    main()
