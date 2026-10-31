# ADR 022 — Suivi du redimensionnement natif

Statut : accepté pour la session 142, 31 octobre 2026.

## Contexte
Le tuilage est suspendu pendant les boutons enfoncés pour ne pas combattre les gestes natifs. Cette garde laisse les voisines immobiles jusqu’au relâchement. La reproduire dans un timer plus rapide ne couvre pas le besoin.

## Décision
Conserver la garde du maintainer. Ouvrir, via le geste existant, une coordination native limitée aux stages à arbre. Lire uniquement la cible par CG ID/PID et calculer des proportions provisoires en mémoire. Seules les voisines sont envoyées au writer commun, avec permission révocable et un lot actif/dernier lot par PID. La publication revient sur MainActor. Une transaction finale valide le contexte et l’arbre initial avant sauvegarde. Le modèle BSP préparé évite la recherche quadratique par mouvement. Aucun code d’OmniWM repris.

## Conséquences
Le rendu de la fenêtre saisie appartient toujours à macOS. Une application lente ne bloque pas directement les autres PID. Un appel AX engagé reste non annulable ; sa suite est invalidée. Les clics, glissers et autres modes restent protégés. La cadence écran ne promet pas de débit AX. Mesures natives et tests requis ; pas d’activité permanente au repos. Les sauvegardes et le journal ne sont pas écrits à chaque image.
