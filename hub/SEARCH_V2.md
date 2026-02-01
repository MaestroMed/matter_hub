# Search v2

Commande unique pour retrouver le passé (ChatGPT archive) :
- FTS (exact) + sémantique (conceptuel)
- filtres temps / rôle / projet
- option group by conversation

## Exemples
Universe-01:
```powershell
python hub/search.py "Primerium Aristote cristaux" --project Universe-01 --top 10
```

Grouper par conversation:
```powershell
python hub/search.py "colonies rouges" --project Universe-01 --group --convos 8 --per-convo 4
```

Filtrer dans le temps:
```powershell
python hub/search.py "Nyx" --since 2024-01-01 --until 2024-12-31 --top 10
```

Role:
```powershell
python hub/search.py "Lumenor" --role user --top 10
```
