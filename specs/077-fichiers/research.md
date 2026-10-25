# Recherche 077

## R1 Lecture du document d'une fenêtre
`kAXDocumentAttribute` donne l'adresse `file://` du document des applications Cocoa à
documents (TextEdit, Aperçu, Pages, Xcode…). Le terminal n'a pas l'autorisation Accessibilité
(essai : `AXIsProcessTrusted() = false`) ; la lecture se fait dans le démon. Elle n'a lieu qu'au
choix d'un fichier, pas à chaque frappe : une lecture par fenêtre gérée, en tâche détachée,
l'application par défaut du fichier d'abord. Le journal note les applications qui exposent un
document, sans chemin : c'est le relevé demandé pour Firefox et Office.

## R2 Spotlight
`NSMetadataQuery` sur le fil principal (notifications), portée `NSMetadataQueryUserHomeScope`,
prédicat `kMDItemDisplayName LIKE[cd] "*saisie*"` et `kMDItemContentTypeTree` parmi
`public.folder`, `public.text`, `public.image`, `com.adobe.pdf`, `public.composite-content`,
`public.spreadsheet`, `public.presentation`. Filtrage des chemins `~/Library`, cachés et
`node_modules`. Tri par `kMDItemLastUsedDate`. Débounce 120 ms, requête précédente arrêtée.

## R3 Stage d'un dossier
Le classement 076 garde une mémoire par stage : la clé `folder:<dossier>` mémorisée à chaque
ouverture d'un fichier dans une stage donne, sans nouveau fichier, la stage la plus récente et
fréquente du dossier. Le contexte est résolu en stage en recalculant `rankingContext` des stages
connues (O(S)).

## R4 Quick Look
`QLPreviewPanel` exige l'activation de Roadie et une chaîne de répondeurs ; `qlmanage -p` montre
l'aperçu dans son propre processus, sans activer Roadie. La barre se ferme avant.

## R5 Ouverture et placement
`NSWorkspace.open(_:withApplicationAt:configuration:)` puis attente de la première nouvelle fenêtre
du paquet (10 s), comme « Nouvelle fenêtre » (074) : la boucle d'attente est mise en commun.
Une application qui ouvre le fichier dans un onglet d'une fenêtre existante ne crée pas de
fenêtre : rien n'est déplacé (limite).

## R6 Relevé réel (25 octobre 2026, 10 fenêtres gérées)
Première lecture : 9 éléments AX trouvés, 0 document. Cause observée : la valeur est une `CFURL`, pas
une chaîne ; la lecture accepte désormais les deux. Relevé ensuite (`axDocumentRead`, sans chemin) :
TextEdit `ok` ; Chrome et T3 Code `notfile` (adresse web, utile pour 082) ; Firefox (2 fenêtres),
Thunderbird, Teams, iTerm2, KeePassXC : `-25212` (aucune valeur). Office non ouvert : non vérifié.
