# Session 104 - Signets de Firefox, Safari et Chrome

## Demande

« Ajouter les signets de Firefox, Safari et Chrome ; soigner Firefox, navigateur de prédilection. »

## Exigences

- FR-001 : section « Signets » dans la barre dès deux lettres : titre, puis étiquettes et mot-clé, puis
  adresse (trois lettres) ; six lignes au plus ; un même signet (adresse ou titre) une seule fois.
- FR-002 : Firefox : tous les profils, y compris ceux de la gestion des profils (`Profile Groups`, avec le
  nom choisi : « Moi », « Google »…) ; dossiers en chemin, étiquettes, mots-clés. La base verrouillée est
  lue sur une copie, journal WAL compris.
- FR-003 : mot-clé Firefox avec `%s` : recherche par mot-clé (« w chat ») ; sans `%s`, le mot-clé tapé seul
  met le signet en tête.
- FR-004 : icône du site lue dans la base des icônes de Firefox et de Chrome, copiée une fois dans
  `~/.roadies/favicons` ; SVG ignoré ; sinon l'icône du navigateur.
- FR-005 : Chrome, Brave et Edge : fichier `Bookmarks` de chaque profil. Safari : `Bookmarks.plist` et liste
  de lecture (accès complet au disque requis pour Roadie).
- FR-006 : Retour ouvre le signet ; s'il vient d'un navigateur qui n'est pas celui par défaut, il s'ouvre
  dans son navigateur. Tab : verbes d'une adresse (ouvrir dans une stage…). ⌘C copie l'adresse.
- FR-007 : onglets ouverts de Firefox (complément de SPEC-082, « Firefox non couvert ») : lus dans la session
  enregistrée (`recovery.jsonlz4`, LZ4) des profils ouverts depuis le lancement ; fenêtre retrouvée par son
  cadre ou le titre de l'onglet actif ; Retour presse l'onglet par l'accessibilité puis montre la fenêtre.
- FR-008 : réglages `bookmarks_enabled` et `bookmark_browsers` dans Paramètres > Recherche ; relecture au plus
  toutes les 60 secondes.

## Limites

Un signet Firefox s'ouvre dans l'instance de Firefox qui reçoit les adresses, pas forcément celle de son
profil. Arc n'est pas lu (format différent). Les onglets Firefox suivent la session écrite toutes les
15 secondes : un onglet ouvert à l'instant peut manquer.
