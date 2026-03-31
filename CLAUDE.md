# CLAUDE.md — matter-hub

## Projet
Hub d'orchestration local (Westworld-style) : indexation ChatGPT, catalogue projets, recherche FTS + sémantique, action ledger. Python/FastAPI + SQLite + Ollama + vanilla JS/BabylonJS.

## Stack & conventions
- **Backend** : Python 3.9+, FastAPI, Jinja2, SQLite (WAL mode)
- **Frontend** : HTML/CSS/JS vanilla, BabylonJS 5.x (CDN) pour Cocoon overlay
- **Embeddings** : Ollama local (nomic-embed-text), port 11434
- **Serveurs** : Hub (port 8900), Ledger (port 8899)
- **Langue du code** : variable names et code en anglais, commentaires et docs en français
- **Pas de frameworks JS** : pas de React, Vue, etc. — vanilla only

## Architecture
```
hub/           → serveurs FastAPI, search, indexation, templates Jinja2
registry/      → build_registry.py, projects.json
connectors/    → Google (Gmail/Drive), futurs connecteurs
```

## Règles de développement
- Toujours lire le fichier avant de le modifier
- Pas de refactoring non demandé — corriger uniquement ce qui est demandé
- Pas de commentaires/docstrings inutiles sur du code non modifié
- Garder les fichiers Python autonomes (scripts exécutables, pas de monolithe)
- SQLite : toujours PRAGMA journal_mode=WAL + synchronous=NORMAL
- Les templates HTML sont dans hub/templates/ (Jinja2)
- Les fichiers statiques (CSS/JS) sont dans hub/ directement

## Style de commits
Format observé dans le repo :
```
<Composant>: <description courte de ce qui change>
```
Exemples : "Ledger v2.2: attach logs, SSE stream, auto project tags", "Hub: listen on 0.0.0.0"

## Workflow optimal (inspiré des best practices)

### Planifier avant de coder
Pour tout changement multi-fichiers ou architectural, commencer par un plan. Demander des clarifications si l'intention est ambiguë plutôt que deviner.

### Paralléliser les recherches
Utiliser les subagents (Agent tool) pour explorer le codebase en parallèle sur des questions indépendantes. Ne pas explorer séquentiellement ce qui peut l'être en concurrence.

### Gérer le contexte activement
- Utiliser /clear entre les tâches distinctes pour éviter la dégradation de contexte
- Lors d'un /compact, préserver : liste des fichiers modifiés, état des tests, décisions prises
- Scopé les investigations : éviter le pattern "explore tout" qui remplit le contexte inutilement

### Slash commands pour les workflows répétitifs
Créer des commandes dans .claude/commands/ pour les tâches fréquentes (ex: lancer les serveurs, tester la recherche, rebuild le registry).

## Lessons learned
<!-- Ajouter ici les erreurs corrigées pour ne pas les répéter -->
<!-- Format : - [contexte] : [ce qu'il ne faut pas faire] → [ce qu'il faut faire] -->

## Compaction instructions
Lors du compactage de contexte, toujours préserver :
- La liste complète des fichiers modifiés dans la session
- L'état actuel des tests ou serveurs en cours
- Les décisions architecturales prises pendant la session
- Les erreurs rencontrées et leurs résolutions
