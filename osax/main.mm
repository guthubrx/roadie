// osax/main.mm
// Entry point Cocoa scripting addition `roadied.osax`.
//
// Chargé dans Dock via `osascript -e 'tell app "Dock" to load scripting additions'`
// (requiert SIP partial off : csrutil enable --without fs --without nvram).
//
// Au load, le constructor `+[ROHooks load]` démarre un thread serveur qui écoute
// `/var/tmp/roadied-osax.sock` et dispatch chaque commande JSON-line sur le main
// thread Dock pour appel CGS privé.
//
// JAMAIS lié au daemon roadied (cf SC-007 SPEC-004) — bundle séparé installé
// manuellement par scripts/install-fx.sh.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "osax_socket.h"

@interface ROHooks : NSObject
@end

@implementation ROHooks

+ (void)load {
    // Constructor Cocoa : appelé une fois par Dock au chargement de la
    // scripting addition. On démarre le serveur socket dans un NSThread
    // dédié pour ne pas bloquer le main thread Dock.
    [NSThread detachNewThreadSelector:@selector(runServerLoop:)
                             toTarget:self
                           withObject:nil];
    NSLog(@"roadied.osax: loaded into %@ (pid %d)",
          [[NSProcessInfo processInfo] processName],
          [[NSProcessInfo processInfo] processIdentifier]);
}

+ (void)runServerLoop:(id)unused {
    @autoreleasepool {
        ROOSAXServer_run();
    }
}

@end
