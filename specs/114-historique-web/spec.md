# Session 114 : historique des adresses web

## Besoin

Reprise d'Alfred (« Historique des adresses ») : retrouver une page déjà vue, sans signet. Alfred ne garde
que les adresses ouvertes depuis Alfred ; Roadie lit l'historique des navigateurs eux-mêmes.

## Règle

- Navigateurs : ceux de `bookmark_browsers`. Firefox (`moz_places` de chaque profil, ordre de fréquence-
  récence de Firefox), Chrome, Brave, Edge (`urls` de `History`), Safari (`History.db`, accès complet au
  disque).
- Fenêtre : `web_history_days` jours (90 par défaut, 0 désactivé, au plus 365) ; 2 000 pages au plus par
  profil. Seules les pages `http` et `https` comptent.
- Barre : section « Historique » après « Signets », 4 lignes au plus, dès deux lettres, par titre puis
  adresse (3 lettres) ; une page déjà proposée en signet n'est pas répétée ; à égalité, la plus visitée.
- Retour ouvre la page comme un signet (navigateur d'origine).
- Lecture hors du fil principal sur une copie de la base, gardée 5 minutes en mémoire ; rien n'est écrit.

## Mesures (ce poste)

- Firefox, profil principal : 7 683 pages sur 90 jours, requête 0,03 s sur la copie (`places.sqlite`
  jusqu'à 15 Mo).
- Safari : 882 pages, 89 sur 90 jours, requête 0,01 s.
