// osax/osax_handlers.mm
// 9 handlers de commandes CGS exposés par l'osax.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "osax_handlers.h"
#import "cgs_private.h"

static NSString *ok(void) { return @"{\"status\":\"ok\"}"; }

static NSString *errorWithCode(NSString *code) {
    return [NSString stringWithFormat:@"{\"status\":\"error\",\"code\":\"%@\"}", code];
}

static CGSConnectionID conn(void) {
    static CGSConnectionID c = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = CGSMainConnectionID(); });
    return c;
}

static NSString *handleNoop(NSDictionary *cmd) { return ok(); }

static NSString *handleSetAlpha(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *alpha = cmd[@"alpha"];
    if (!wid || !alpha) return errorWithCode(@"invalid_parameter");
    float a = MAX(0.0f, MIN(1.0f, [alpha floatValue]));
    CGError err = SLSSetWindowAlpha(conn(), (CGWindowID)[wid unsignedIntValue], a);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

// Ombre : density 0.0 (invisible) .. 1.0 (default).
// Std dev par défaut 64 (effet macOS standard). Offsets 0/0.
static NSString *handleSetShadow(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *density = cmd[@"density"];
    if (!wid || !density) return errorWithCode(@"invalid_parameter");
    float d = MAX(0.0f, MIN(1.0f, [density floatValue]));
    // std_dev (blur), density, offset_x, offset_y, flags (0).
    // Pour density=0 : invisible. Pour density=1 + std_dev=64 : équivalent macOS.
    float stdDev = (d > 0.0f) ? 64.0f : 0.0f;
    CGError err = SLSSetWindowShadowParameters(conn(), (CGWindowID)[wid unsignedIntValue],
                                                stdDev, d, 0, 0, 0);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

static NSString *handleSetBlur(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *radius = cmd[@"radius"];
    if (!wid || !radius) return errorWithCode(@"invalid_parameter");
    int r = MAX(0, MIN(100, [radius intValue]));
    CGError err = SLSSetWindowBackgroundBlurRadius(conn(), (CGWindowID)[wid unsignedIntValue], r);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

static NSString *handleSetTransform(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *scale = cmd[@"scale"];
    NSNumber *tx = cmd[@"tx"];
    NSNumber *ty = cmd[@"ty"];
    if (!wid || !scale) return errorWithCode(@"invalid_parameter");
    CGFloat s = MAX(0.0, MIN(5.0, [scale doubleValue]));
    CGAffineTransform t = CGAffineTransformMakeScale(s, s);
    if (tx) t.tx = [tx doubleValue];
    if (ty) t.ty = [ty doubleValue];
    CGError err = SLSSetWindowTransform(conn(), (CGWindowID)[wid unsignedIntValue], t);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

static NSString *handleSetLevel(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *level = cmd[@"level"];
    if (!wid || !level) return errorWithCode(@"invalid_parameter");
    int l = MAX(-2000, MIN(2000, [level intValue]));
    CGError err = SLSSetWindowLevel(conn(), (CGWindowID)[wid unsignedIntValue], l);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

// Frame osax = move only (origine). Resize via AX côté daemon.
static NSString *handleSetFrame(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *x = cmd[@"x"];
    NSNumber *y = cmd[@"y"];
    if (!wid || !x || !y) return errorWithCode(@"invalid_parameter");
    CGPoint origin = CGPointMake([x doubleValue], [y doubleValue]);
    CGError err = SLSMoveWindow(conn(), (CGWindowID)[wid unsignedIntValue], &origin);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

static CGSSpaceID spaceIDForUUID(NSString *uuid) {
    CFArrayRef displays = SLSCopyManagedDisplaySpaces(conn());
    if (!displays) return 0;
    CGSSpaceID found = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(displays); i++) {
        NSDictionary *display = (__bridge NSDictionary *)CFArrayGetValueAtIndex(displays, i);
        NSArray *spaces = display[@"Spaces"];
        for (NSDictionary *space in spaces) {
            NSString *u = space[@"uuid"];
            if ([u isEqualToString:uuid]) {
                found = (CGSSpaceID)[space[@"id64"] unsignedLongLongValue];
                break;
            }
        }
        if (found) break;
    }
    CFRelease(displays);
    return found;
}

static NSString *handleMoveWindowToSpace(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSString *uuid = cmd[@"space_uuid"];
    if (!wid || ![uuid isKindOfClass:[NSString class]]) {
        return errorWithCode(@"invalid_parameter");
    }
    CGSSpaceID spaceID = spaceIDForUUID(uuid);
    if (spaceID == 0) return errorWithCode(@"invalid_parameter");

    NSArray *windowList = @[wid];
    NSArray *spaceList = @[@(spaceID)];
    SLSAddWindowsToSpaces(conn(), (__bridge CFArrayRef)windowList,
                          (__bridge CFArrayRef)spaceList);
    return ok();
}

static NSString *handleSetSticky(NSDictionary *cmd) {
    NSNumber *wid = cmd[@"wid"];
    NSNumber *sticky = cmd[@"sticky"];
    if (!wid || !sticky) return errorWithCode(@"invalid_parameter");
    CGWindowID w = (CGWindowID)[wid unsignedIntValue];
    uint32_t mask = 0;
    SLSGetWindowEventMask(conn(), w, &mask);
    if ([sticky boolValue]) {
        mask |= kCGSStickyWindowFlag;
    } else {
        mask &= ~kCGSStickyWindowFlag;
    }
    CGError err = SLSSetWindowEventMask(conn(), w, mask);
    return err == kCGErrorSuccess ? ok() : errorWithCode(@"cgs_failure");
}

// Bascule vers un space par UUID (pattern yabai). Utilise le contexte privilégié
// Dock pour que WindowServer rerender la visibilité des fenêtres (sinon le
// space change mais les windows restent visibles depuis l'ancien space).
static NSString *handleSpaceFocus(NSDictionary *cmd) {
    NSString *uuid = cmd[@"space_uuid"];
    if (![uuid isKindOfClass:[NSString class]]) {
        return errorWithCode(@"invalid_parameter");
    }
    CFArrayRef displays = CGSCopyManagedDisplaySpaces(conn());
    if (!displays) return errorWithCode(@"cgs_failure");

    NSString *displayUUID = nil;
    CGSSpaceID spaceID = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(displays); i++) {
        NSDictionary *display = (__bridge NSDictionary *)CFArrayGetValueAtIndex(displays, i);
        for (NSDictionary *space in display[@"Spaces"]) {
            if ([space[@"uuid"] isEqualToString:uuid]) {
                displayUUID = display[@"Display Identifier"];
                NSNumber *sidNum = space[@"ManagedSpaceID"] ?: space[@"id64"] ?: space[@"id"];
                spaceID = (CGSSpaceID)[sidNum unsignedLongLongValue];
                break;
            }
        }
        if (displayUUID) break;
    }
    CFRelease(displays);

    if (!displayUUID || spaceID == 0) return errorWithCode(@"not_found");
    CGSManagedDisplaySetCurrentSpace(conn(), (__bridge CFStringRef)displayUUID, spaceID);
    return ok();
}

NSString *ROOSAXHandlers_dispatch(NSString *name, NSDictionary *cmd) {
    if ([name isEqualToString:@"noop"])               return handleNoop(cmd);
    if ([name isEqualToString:@"set_alpha"])          return handleSetAlpha(cmd);
    if ([name isEqualToString:@"set_shadow"])         return handleSetShadow(cmd);
    if ([name isEqualToString:@"set_blur"])           return handleSetBlur(cmd);
    if ([name isEqualToString:@"set_transform"])      return handleSetTransform(cmd);
    if ([name isEqualToString:@"set_level"])          return handleSetLevel(cmd);
    if ([name isEqualToString:@"set_frame"])          return handleSetFrame(cmd);
    if ([name isEqualToString:@"move_window_to_space"]) return handleMoveWindowToSpace(cmd);
    if ([name isEqualToString:@"set_sticky"])         return handleSetSticky(cmd);
    if ([name isEqualToString:@"space_focus"])        return handleSpaceFocus(cmd);
    return errorWithCode(@"unknown_command");
}
