// cgs_private.h
// Déclarations CGS / SkyLight privées utilisées par les handlers de l'osax.
// JAMAIS incluses par le daemon Swift (cf SC-007 SPEC-004).
//
// Sur macOS Tahoe 26+ Apple a renommé les symboles `CGSSet*` → `SLSSet*`
// (SLS = SkyLight Server). On utilise les vrais noms exposés par
// /System/Library/PrivateFrameworks/SkyLight.framework — vérifiables via
// `dyld_info -exports SkyLight | grep _SLSSetWindow`.
//
// Sources : reverse-engineered headers communs yabai / Hammerspoon /
// SkyLightWindow. Stables sur macOS 14 → 26.
//
// Pour le projet roadie : utilisé uniquement dans les handlers .mm de l'osax
// chargé par Dock. Aucune utilisation depuis le daemon `roadied`.

#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int CGSConnectionID;
typedef uint64_t CGSSpaceID;

// La connexion principale du process appelant (Dock dans notre cas).
// Symbole exposé par SkyLight, signature stable.
CGSConnectionID CGSMainConnectionID(void);

// Alpha 0.0 .. 1.0.
CGError SLSSetWindowAlpha(CGSConnectionID cid, CGWindowID wid, float alpha);

// Shadow parameters (std_dev = blur, density = opacité ombre, offset, flags).
// Pour density 0.0 → ombre invisible. Pour rétablir : density 1.0, std_dev 64, offsets 0.
CGError SLSSetWindowShadowParameters(CGSConnectionID cid, CGWindowID wid,
                                      float std_dev, float density,
                                      int x_offset, int y_offset, int flags);

// Background blur radius (Gaussian) ; valeurs typiques 0..100.
CGError SLSSetWindowBackgroundBlurRadius(CGSConnectionID cid, CGWindowID wid, int radius);

// Transform : matrice 3x3 affine. Pour Roadie : scale + translate.
CGError SLSSetWindowTransform(CGSConnectionID cid, CGWindowID wid, CGAffineTransform transform);

// Niveau de fenêtre (NSWindowLevel int).
CGError SLSSetWindowLevel(CGSConnectionID cid, CGWindowID wid, int level);

// Déplace la fenêtre (origine seulement). Le resize via SkyLight est fragile
// et se fait côté daemon via AX. setFrame osax = move only.
CGError SLSMoveWindow(CGSConnectionID cid, CGWindowID wid, const CGPoint *origin);

// Add/remove window in spaces (FR-024 SPEC-003 / SPEC-010 cross-desktop).
void SLSAddWindowsToSpaces(CGSConnectionID cid, CFArrayRef windowList, CFArrayRef spaceList);
void SLSRemoveWindowsFromSpaces(CGSConnectionID cid, CFArrayRef windowList, CFArrayRef spaceList);

// Sticky : le bit kCGSStickyWindowFlag est dans l'event mask.
CGError SLSSetWindowEventMask(CGSConnectionID cid, CGWindowID wid, uint32_t mask);
CGError SLSGetWindowEventMask(CGSConnectionID cid, CGWindowID wid, uint32_t *mask);

#define kCGSStickyWindowFlag 0x100000

// Cross-référence Space UUID → CGSSpaceID (pour move_window_to_space).
// Retourne CFArray d'NSDictionary par display contenant `Spaces[].uuid` et `id64`.
CFArrayRef SLSCopyManagedDisplaySpaces(CGSConnectionID cid);

#ifdef __cplusplus
}
#endif

#endif // CGS_PRIVATE_H
