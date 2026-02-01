# Action Ledger

Le ledger est le journal d'activité de Greydawn (actions exécutées), stocké localement en SQLite.

## Fichiers
- `hub/actions.sqlite` : base de données
- `hub/action_log.py` : bibliothèque de log
- `hub/actions_query.py` : CLI de requêtes

## Exemples
Afficher les 20 dernières actions:
```powershell
python hub/actions_query.py --limit 20 --format compact
```

Afficher les erreurs:
```powershell
python hub/actions_query.py --status error --limit 50
```

Rechercher par texte:
```powershell
python hub/actions_query.py --q "Universe-01" --limit 50 --format compact
```

## Convention (à respecter)
Chaque script important doit encapsuler son travail dans `with log_event(...)`.
