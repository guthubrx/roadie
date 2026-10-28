# Session 116 : documents récents d'une application

## Besoin

Reprise d'Alfred (« Recent Documents ») : rouvrir un document fermé dont on a oublié le nom, en partant de
l'application qui l'a ouvert.

## Faisabilité (vérifiée le 28 octobre 2026, macOS 26)

- macOS garde le menu Fichier > Ouvrir récent de chaque application dans
  `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/
  <identifiant en minuscules>.sfl4` (90 applications ici). Format non documenté : archive `NSKeyedArchiver`,
  racine `items`, chaque élément avec un signet de fichier `Bookmark`. Le chemin se lit dans le signet sans
  le résoudre (`URL.resourceValues(forKeys:fromBookmarkData:)`) : rien n'est monté ni ouvert.
- Microsoft Office laisse cette liste vide (Word, Excel : 0 élément). Sa liste est dans
  `~/Library/Containers/<identifiant>/Data/Library/Preferences/<identifiant>.securebookmarks.plist` : clés
  `file://…`, date `kLastUsedDateKey` (Word : 292 entrées, 147 fichiers encore présents).
- Mesures : Aperçu 10 éléments, 9 présents, 49 ms ; TextEdit 10, 1 présent ; Word 147 présents, 77 ms.

## Règle

- Verbe « Documents récents… » des applications, après « Nouvelle fenêtre ici ». Troisième étape :
  « Application › Documents récents », 20 documents au plus, encore présents, sans doublon ; Office d'abord
  par date d'usage, puis la liste de macOS dans son ordre. La saisie filtre par nom.
- Retour ouvre le document avec cette application (`NSWorkspace.open(_:withApplicationAt:)`).
- La liste d'Office n'est lue que pour `com.microsoft.*`, à la demande : macOS peut demander l'accès aux
  données de l'autre application à ce moment-là.
- Un document n'est jamais une destination d'un autre verbe.

## Limites

- Le format `.sfl4` peut changer avec macOS ; `.sfl3` et `.sfl2` sont aussi lus. Une liste illisible donne
  une étape vide.
