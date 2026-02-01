# Google connector (Gmail + Drive)

Objectif: indexer Gmail (tout) + une sélection Drive, en local (SQLite FTS + index sémantique).

⚠️ Nécessite OAuth. On évite d'exfiltrer: on stocke les tokens localement.

## Étapes (manuel, 1 fois)
1. Créer un projet Google Cloud
2. Activer APIs: Gmail API, Google Drive API
3. Configurer l'écran de consentement OAuth
4. Créer des identifiants OAuth (Desktop app)
5. Télécharger `client_secret.json` et le placer ici.

## Notes
- Gmail "tout" peut être énorme: on pourra commencer par headers + sujets, puis corps.
- Drive: idéalement on définit une whitelist de dossiers.
