# Spécification 095 - Navigateur suivi pour les workflows, texte d'attente de la grille, trace du focus

Demande du 27 octobre 2026, après essai de la 094 : « la bascule fonctionne pour la recherche mais pas
sûr que la fenêtre navigateur ait bien reçu le focus » ; « ok pour un texte d'attente "Loading..." » ;
« ok pour aller au navigateur quand un workflow ouvre une adresse ».

## Constat (journal, 06:17)
Première recherche : `launcher.follow_browser` fenêtre 498 (celle de l'onglet), activée ; 2 s plus tard
le sélecteur de fenêtres a activé Chrome (geste au clavier, `switcher.activate`). Seconde recherche
(06:17:22) : aucun événement ; le code s'arrêtait sans trace quand aucune fenêtre n'était trouvée.
Hypothèse non vérifiée : lecture des fenêtres vide à cet instant.

## Exigences
- **FR-001 Trace.** Chaque passage au navigateur est noté : fenêtre trouvée ou non, essai, application
  au premier plan, fenêtre de l'onglet ou de repli, focus clavier relu 300 ms après l'activation
  (`keyboardFocus`). Sans fenêtre au premier essai : second essai 700 ms plus tard.
- **FR-002 Workflows.** La brique Open URL et la recherche web d'un workflow (adresses http/https)
  suivent le navigateur comme la barre.
- **FR-003 Attente.** Une grille alimentée par un script ouvre la barre tout de suite sur son texte
  d'attente (`loadingtext`, sinon « Loading… ») ; les tuiles remplacent la ligne d'attente dans la même
  barre (saisie gardée, présélection appliquée) ; un échec du script remplace la ligne par sa raison.
  Une barre fermée entre-temps n'est pas rouverte.

## Hors périmètre
Forme des tuiles (`imageaspect`), maquette proposée ; ouvertures de fichiers par les workflows.
