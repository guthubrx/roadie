# Livraison 034 — 2026-10-15

Correction installée, signée et redémarrée. UUID compilé et installé identique :
2B510D42-C812-384F-952E-59E17AA95A6C. Certificat conservé :
78a75e8032f190a20072eb91cc2919aac344ef78. PID actif : 15020.
Quatre contrôles santé OK ; les neuf fenêtres communes gardent leur groupe.
Configuration inchangée ; 46 fichiers parallèles vérifiés inchangés.

## Preuves

- Sans correctif : 15 assertions échouent sur la régression finale.
- Avec correctif : trois cas passent, avec cent passes de sécurité sans boucle.
- Suite isolée : 1 484 tests dans 162 suites.
- Suite combinée : 1 551 tests dans 169 suites.
- Exécution séquentielle : swift test --no-parallel, sans assertion ni délai assoupli.
- Contrôle sur le Mac : fenêtre initiale interne, groupe externe, disponibilité AX
  retardée de trois secondes. Les deux voisines restent à leurs cadres initiaux aux
  trois relevés d’attente. Un événement d’attente, un événement de disponibilité ;
  placement sans échec et stabilité à 216 ms. Fermeture automatique, neuf cadres et
  groupes précédents retrouvés. Aucune manipulation des terminaux de l’utilisateur.

Le contrôle physique final utilise la fenêtre synthétique 103268. Le terminal
historique 99751 n’est pas rejoué. La cause AX précise des deux échecs historiques
n’avait pas été enregistrée ; le défaut de reprise observé et le cas d’indisponibilité
avant toute écriture sont couverts par les tests et le contrôle réel ci-dessus.

## Reproduction et sauvegarde

Le patch combiné, compressé en gzip, est relatif à 893c5fc6a7690ccc5737aee37e25f9600226621e.
Ses 264 empreintes Sources/Tests ont été vérifiées dans un index Git isolé.
La livraison conserve le travail parallèle déjà installé. Ne pas installer le seul
main tant que ce travail n’y est pas intégré.

Application : /Users/moi/Applications/Roadie.app
Configuration : /Users/moi/.config/roadies/roadies.toml
Copie de compilation combinée : /private/tmp/roadie031-livraison
Sauvegarde application, CLI, configuration, état : /private/tmp/roadie034-before-install
Incident initial : /private/tmp/roadie-terminal-20261015-1224
Contrôle réel et captures privées : /private/tmp/roadie034-probe
Sources de l’application de contrôle, à conserver avec son Info.plist et le lanceur :
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/034-reprise-placement/validation/probe.swift
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/034-reprise-placement/validation/probe-Info.plist
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/034-reprise-placement/validation/probe-run.py

Les captures et les relevés complets restent locaux. Les résumés versionnés ne
contiennent que les identifiants, cadres, délais et résultats nécessaires au contrôle.

Patch compressé :
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/034-reprise-placement/validation/delivery.patch.gz
Le manifeste conserve les empreintes de l’archive et du patch décompressé.
