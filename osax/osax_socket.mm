// osax/osax_socket.mm
// Serveur socket Unix pour les commandes daemon → Dock.
// Protocol : JSON-lines (1 ligne = 1 commande, 1 ligne = 1 ack).

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>
#import <pthread.h>
#import "osax_socket.h"
#import "osax_handlers.h"

static const char *kSocketPath = "/var/tmp/roadied-osax.sock";

static NSString *handleCommand(NSDictionary *cmd) {
    NSString *name = cmd[@"cmd"];
    if (![name isKindOfClass:[NSString class]]) {
        return @"{\"status\":\"error\",\"code\":\"unknown_command\"}";
    }
    return ROOSAXHandlers_dispatch(name, cmd);
}

static void *handleClient(void *arg) {
    int fd = (int)(intptr_t)arg;
    @autoreleasepool {
        // Vérification UID : le client doit avoir le même uid que le owner
        // de la socket (utilisateur courant).
        uid_t peerUID = 0;
        gid_t peerGID = 0;
        if (getpeereid(fd, &peerUID, &peerGID) != 0 || peerUID != getuid()) {
            NSLog(@"roadied.osax: rejected connection from foreign uid=%d", peerUID);
            close(fd);
            return NULL;
        }

        // Boucle reader : lit JSON-lines, dispatch sur main thread, write ack.
        NSMutableData *buffer = [NSMutableData data];
        char chunk[4096];
        while (true) {
            ssize_t n = read(fd, chunk, sizeof(chunk));
            if (n <= 0) break;
            [buffer appendBytes:chunk length:n];

            // Découpe sur '\n' et traite chaque ligne complète.
            const char *bytes = (const char *)buffer.bytes;
            NSUInteger lineStart = 0;
            for (NSUInteger i = 0; i < buffer.length; i++) {
                if (bytes[i] == '\n') {
                    NSData *lineData = [NSData dataWithBytes:bytes + lineStart
                                                       length:i - lineStart];
                    NSString *reply = nil;
                    NSError *err = nil;
                    NSDictionary *cmd = [NSJSONSerialization JSONObjectWithData:lineData
                                                                          options:0
                                                                            error:&err];
                    if (![cmd isKindOfClass:[NSDictionary class]]) {
                        reply = @"{\"status\":\"error\",\"code\":\"invalid_parameter\"}";
                    } else {
                        // Dispatch sur main thread (CGS calls doivent être
                        // sur le main thread Dock, sinon Dock crash).
                        __block NSString *r = nil;
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            r = handleCommand(cmd);
                        });
                        reply = r ?: @"{\"status\":\"error\",\"code\":\"cgs_failure\"}";
                    }
                    NSData *replyData = [[reply stringByAppendingString:@"\n"]
                                         dataUsingEncoding:NSUTF8StringEncoding];
                    write(fd, replyData.bytes, replyData.length);
                    lineStart = i + 1;
                }
            }
            if (lineStart > 0) {
                [buffer replaceBytesInRange:NSMakeRange(0, lineStart)
                                  withBytes:NULL length:0];
            }
        }
        close(fd);
    }
    return NULL;
}

void ROOSAXServer_run(void) {
    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) {
        NSLog(@"roadied.osax: socket() failed errno=%d", errno);
        return;
    }
    unlink(kSocketPath);
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"roadied.osax: bind(%s) failed errno=%d", kSocketPath, errno);
        close(srv);
        return;
    }
    chmod(kSocketPath, 0600);
    if (listen(srv, 4) < 0) {
        NSLog(@"roadied.osax: listen() failed errno=%d", errno);
        close(srv);
        return;
    }
    NSLog(@"roadied.osax: listening on %s", kSocketPath);

    while (true) {
        int client = accept(srv, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            NSLog(@"roadied.osax: accept() failed errno=%d", errno);
            break;
        }
        // Thread par client (≤ 4 simultanés vu le listen backlog).
        pthread_t tid;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        pthread_create(&tid, &attr, handleClient, (void *)(intptr_t)client);
        pthread_attr_destroy(&attr);
    }
    close(srv);
    unlink(kSocketPath);
}
