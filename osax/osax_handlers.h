// osax_handlers.h

#ifndef OSAX_HANDLERS_H
#define OSAX_HANDLERS_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Dispatch sur le nom de la commande. Retourne une string JSON (ack ou error).
// Doit être appelé sur le main thread Dock (les CGS calls le requièrent).
NSString *ROOSAXHandlers_dispatch(NSString *name, NSDictionary *cmd);

#ifdef __cplusplus
}
#endif

#endif
