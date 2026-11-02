# Feature Specification: Gestes de fenêtre par modificateur

<!-- SPEC-FORMALISM:START -->
## Fiche Synthèse
Spec: 151-gestes-modificateurs
Titre: Déplacer et redimensionner depuis le contenu d’une fenêtre
Statut: In Progress
Priorité: P1
Tâches: 3/5 (60%)
Tests: 16/16 (100%)
Résumé:
- Contexte: déplacement natif limité au titre et redimensionnement aux bords.
- Objectif: Ctrl+glisser gauche pour déplacer ; Ctrl+Alt+glisser gauche pour redimensionner.
- Dépendances: SPEC-142, SPEC-143, SPEC-144, SPEC-149
Fichiers:
- spec.md: ✓
- plan.md: ✓
- tasks.md: ✓
<!-- SPEC-FORMALISM:END -->

Demande et choix des modificateurs validés par l’utilisateur le2novembre2026. Les deux combinaisons sont réglables à chaud dans Tuilage, avec désactivation indépendante. Aucune dépendance BTT ni modification des règles de l’application.

## Parcours
1. Maintenir Ctrl, appuyer sur le bouton gauche n’importe où dans une fenêtre normale visible, puis glisser : déplacer la vraie fenêtre et réutiliser la géométrie de dépôt existante (stage, réorganisation, écran). Les réglages d’aperçu et de suivi des voisines restent applicables.
2. Maintenir Ctrl+Alt puis glisser gauche : redimensionner depuis le contenu. Le bord/coin le plus proche est choisi au début. Pour une fenêtre tuilée, choisir seulement les séparations effectivement mobiles et adapter les voisines. Respecter les minima et refus des applications. Une fenêtre tuilée seule n’a pas de séparation à réduire.
3. Les touches sont fixées au début du geste ; les relâcher pendant le glisser ne doit pas laisser la souris bloquée. Relâcher le bouton valide. Échap annule et restaure la géométrie si le contexte est encore valide.
4. Un clic modifié sans glisser doit conserver son sens normal, notamment Ctrl+clic du menu contextuel. Le geste intercepté ne sélectionne pas de texte, ne déclenche pas un lien ou un bouton.
5. Exclure le bureau, les menus et le plein écran natif. Ne jamais viser une fenêtre cachée derrière une surface non gérée. Les fenêtres ordinaires flottantes restent manipulables.

## Fiabilité
Aucune lecture AX dans le callback souris ni par événement de mouvement. Une seule capture par processus écrivain, un seul dispatcher coalescé pour source et voisines. Sauvegarde des ratios au relâchement avec contrôle d’arbre/contexte. Une commande externe, un changement de stage/configuration ou la disparition de la fenêtre révoque le geste, sans remettre une ancienne disposition sur une nouvelle commande. Pas de nouvelle permission imposée.
