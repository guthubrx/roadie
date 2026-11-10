# 032 - Section publique Launcher compatible avec les anciens fichiers

Date : 2026-11-10. Statut : accepté, décision utilisateur D3 de la session 155.

## Contexte

Les réglages du lanceur sont historiquement sous `experimental.target_mode`. Le même
modèle sert à ses touches et à la recherche à l'écran. Dupliquer ses propriétés dans une
nouvelle structure obligerait à synchroniser deux catalogues et tous les consommateurs.

## Décision

`[launcher]` accepte les mêmes clés. Le décodage réutilise TargetModeConfig avec les valeurs
héritées comme valeurs de repli : chaque clé nouvelle l'emporte et chaque clé absente garde
l'ancienne valeur. Les tableaux sont remplacés comme une valeur, sans concaténation.
Les deux sections doivent contenir des valeurs du bon type.

Les Paramètres gardent leurs identifiants et catégories. Ils écrivent la clé concernée sous
`[launcher]` et retirent son ancienne écriture. Réinitialiser retire les deux écritures pour
éviter une réapparition de l'ancienne valeur. Cette migration est progressive, par clé ;
elle ne réencode pas le document. Les commentaires et les autres réglages sont préservés.
Les listes existantes utilisent le même éditeur structuré et la même lecture sémantique.

Le modèle interne et son encodage programmatique restent compatibles avec les versions
précédentes. Une ancienne version de Roadie ne lit pas `[launcher]` : le retour à une version
antérieure demande de replacer les clés dans `experimental.target_mode`, ou de reprendre la
sauvegarde conservée par l'éditeur. Aucun changement automatique du fichier utilisateur.

## Vérification

Spec155LauncherTests : ancien/nouveau fichier, priorité par clé, touches héritées, tableaux
vides et tableaux de tables, clé inconnue, listes, édition/reset et écriture réelle via
SettingsService avec relecture du fichier. Tests écrits avant la correction et échec observé
sur l'ancien code. La fenêtre graphique garde sa présentation et ses catégories.

## Conséquences

Aucune nouvelle dépendance et aucun second type de configuration. Deux sections restent
lisibles pendant la transition. La forme publique documentée est `[launcher]` ; la section
ancienne reste acceptée. Les parcours restent linéaires sur le fichier ou les clés.
