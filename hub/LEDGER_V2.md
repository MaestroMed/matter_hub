# Ledger v2 (web UI)

## Pourquoi
Un ledger world-class = pas seulement une DB + CLI, mais aussi une UI pour:
- naviguer
- filtrer
- rechercher
- inspecter les détails (params/extra/error)

## Démarrage
```powershell
cd D:\PROJECTS\matter-hub
python hub\ledger_server.py
```

Puis ouvrir:
- http://127.0.0.1:8899/

## API
- `GET /api/events?limit=100&kind=...&status=...&q=...&since=...&until=...`
- `GET /api/events/{id}`

## Notes
- Localhost only.
- Refresh auto toutes les 5s.
