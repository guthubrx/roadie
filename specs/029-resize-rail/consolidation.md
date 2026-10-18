# Consolidation du 18 octobre 2026

Les corrections de la session 029 sont déjà intégrées dans `main`, notamment par
`06245802`. Le commit documentaire `00fc6740` et les documents de travail sont
réunis ici pour conserver leur contexte. Aucun ancien fichier Swift n'est réintroduit.

Les décisions suivantes ont évolué depuis ces documents :

- Les sessions 031–033 ont remplacé le badge permanent séparé par les légendes
  configurables du rail. L'ancien test du badge permanent est donc dépassé.
- La session 037 traite la présence réelle des fenêtres et la disponibilité AX
  avant leur placement. Les anciens filtres fondés seulement sur les candidats
  au tuilage ne doivent pas remplacer ces contrôles.
- La session 039 accepte une observation de redimensionnement commencée à temps,
  même si la lecture AX est lente. Les anciennes conditions temporelles ont été corrigées.

T054 (intégration Git et nettoyage) est traitée par cette consolidation.
T053 reste une réserve historique : aucun nouveau geste natif n'a été vérifié
pendant ce nettoyage. La dernière suite validée compte 1 603 tests ; les limites
de validation sont consignées dans ../039-anomalies-journee/validation.md.

Les copies originales, index et différences sont conservés dans
/Users/moi/Archives/roadie-consolidation-20261018.
