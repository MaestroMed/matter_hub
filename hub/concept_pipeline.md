# Concept pipeline (univers éparpillé → canon)

Objectif: retrouver tout ce qui concerne un univers (noms, personnages, lieux, lore, règles, timelines, style visuel) dans des sources dispersées (ChatGPT, Midjourney, Gemini, docs locaux), puis produire:
- un **canon** (source of truth)
- des **boards** (characters, environments, factions, items)
- une **chronologie**
- un **glossaire**
- un **style guide** (art + écriture)

## Phase 1 — Récupération / index
- ChatGPT export → SQLite FTS + index sémantique
- Ajout futurs: Midjourney (prompts + images), Gemini, docs Cursor

## Phase 2 — Extraction
- Définir une liste de *signaux* (noms d'univers, personnages, lieux)
- Lancer des requêtes sémantiques + FTS pour rassembler les fragments
- Regrouper par thèmes (personnages/lieux/événements/règles)

## Phase 3 — Canonisation
- Dédupliquer, résoudre les contradictions
- Écrire une version canonique + versions alternatives (si besoin)

## Phase 4 — Boards & assets
- Boards texte (fiches)
- Génération d'images (plus tard) + classement + références

## Phase 5 — Itération
- Boucles: tu valides, j'affine, on pousse le canon.
