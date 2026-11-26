# Spec 169 — Repli OCR local macOS Vision sur la recherche à l’écran

## Contexte & Problème
La recherche à l’écran de Roadie (`Capslock+F` / `roadie targets screen`) s’appuie sur l’arbre Accessibilité macOS. Certaines fenêtres (applications Electron sans boost, canvas web, PDF scannés, bureaux distants RDP/VNC, interfaces personnalisées) publient peu ou pas d’éléments AX cliquables.

## Exigences fonctionnelles
- **FR-001 (Interrupteur explicite, désactivé par défaut)** : Réglage `experimental.app_targets.ocr_fallback` (`Bool`, défaut `false`) et `experimental.app_targets.ocr_fallback_threshold` (`Int`, `0...30`, défaut `3`). Quand `ocr_fallback = false`, aucune capture d’écran ni requête `Vision` n’est jamais lancée (coût CPU/RAM = 0).
- **FR-002 (Repli intelligent uniquement sur fenêtres pauvres en AX)** : Lorsque `ocr_fallback = true`, l’OCR local ne s’exécute que sur les fenêtres où le scan AX a trouvé au plus `ocr_fallback_threshold` cibles, évitant tout surcoût sur les applications natives bien accessibles.
- **FR-003 (100 % local, respect des permissions)** : Utilise `VNRecognizeTextRequest` (Apple Vision, `.fast`, exécution locale sur Neural Engine/CPU, zéro réseau). Vérifie `CGPreflightScreenCaptureAccess()` avant capture afin de ne jamais déclencher de boîte système inattendue.
- **FR-004 (Géométrie Retina multi-écrans & déduplication)** : Convertit exactement les boîtes normalisées Vision (origine bas-gauche `[0..1]`) en coordonnées AX (origine haut-gauche, incluant écrans à coordonnées négatives), et écarte les observations redondantes avec une cible AX déjà présente.
- **FR-005 (Clic sûr sur cible OCR)** : Le clic sur une cible `app:<pid>/ocr:...` vérifie le focus fenêtre (`waitForFocus`) et la stabilité de position de la fenêtre avant d’envoyer l’événement souris.
- **FR-006 (Mesure de charge réelle)** : Mesurer latence (`ms`) et empreinte mémoire (`phys_footprint`) sur des images 1080p et 1440p dans la suite de tests.
