// osax_socket.h — Header partagé entre main.mm et osax_socket.mm

#ifndef OSAX_SOCKET_H
#define OSAX_SOCKET_H

#ifdef __cplusplus
extern "C" {
#endif

// Démarre le serveur socket Unix. Boucle bloquante (à appeler depuis un thread
// dédié). Path fixé `/var/tmp/roadied-osax.sock`, mode 0600, owner = user
// courant. Vérifie l'UID du peer à chaque accept.
void ROOSAXServer_run(void);

#ifdef __cplusplus
}
#endif

#endif
