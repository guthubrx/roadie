# Implémentation de l'audit 035

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

Sept mécanismes corrigés, sans modifier le daemon installé : publication périmée de configuration ; macro non validée ; lecture quadratique du journal ; identifiants JSON invalides ; IDs de stages TOML vides ; nombres TOML non finis ; perte d'événements autour d'une ligne UTF-8 abîmée.

Les cinq identifiants et les deux chemins d'abonnement sont conservés comme sites distincts dans les constats. Les formats scalaires, les défauts valides, les événements sémantiques, les rotations et les protections de persistance sont préservés.

1565 tests Swift passent dans 176 suites (21,658 s de tests, 30,761 s de contrôle avec compilation). Le delta contient sept fichiers produit et sept fichiers de test. Aucun commit, aucune installation, aucun redémarrage. La version source auditée inclut les travaux parallèles 029 déjà installés ; leur delta initial est conservé à part.

Le rapprochement central garde un coût quadratique de mise à jour des cadres. Benchmark : 1,884 / 30,181 / 116,670 ms pour 200 / 800 / 1600 fenêtres synthétiques. Cette mesure n'est pas une latence de tiling en production. Une correction par lot doit préserver l'ordre du focus, des pins et bookmarks ; elle n'est pas remplacée par un nouveau cache implicite.
