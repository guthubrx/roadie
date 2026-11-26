# Plan — Spec 169 : Repli OCR local Vision

1. **Configuration (`RoadieCore`)** :
   - Ajouter `ocrFallbackEnabled: Bool = false` (`ocr_fallback`) et `ocrFallbackThreshold: Int = 3` (`ocr_fallback_threshold`, borné `0...30`) dans `AppTargetsConfig`.
   - Déclarer les clés dans `ConfigValidationRules.knownKeys["experimental.app_targets"]` et la borne dans `ConfigLoaderAndValidation.swift` / `SettingsCatalog.swift`.
2. **Module isolé (`Sources/RoadieDaemon/ScreenSearchOCRService.swift`)** :
   - Conversion pure `normalizedBoxToAXRect(_:in:)`.
   - Déduplication contre les cibles AX existantes (`overlapsExisting`).
   - Exécution `VNRecognizeTextRequest` (`.fast`, local FR/EN) avec `OCRScanMetrics` (`elapsedMs`, `imageWidth`, `imageHeight`, `observations`, `retained`, `footprintDeltaKB`).
   - Capture fenêtre conditionnée à `CGPreflightScreenCaptureAccess()`.
3. **Intégration `AppTargetQueryService.swift`** :
   - Déclenchement conditionnel dans `frontmostWindowCandidates` et `scanVisibleWindows` lorsque `config.ocrFallbackEnabled && targets.count <= config.ocrFallbackThreshold`.
   - Support du clic sécurisé pour les cibles OCR dans `LiveAppTargetProvider.click(...)` (vérification focus + frame fenêtre).
4. **Tests & benchmark réel (`Tests/RoadieDaemonTests/Spec169ScreenSearchOCRTests.swift`)** :
   - Config défaut `false`, TOML, géométrie Retina/multi-écrans négatifs, déduplication, et exécution réelle `Vision` sur images synthétiques 1080p / 1440p avec mesure de latence et mémoire.
