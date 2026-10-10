import Darwin

/// Vivacité d'un processus, testée en un seul endroit (SPEC-016 T219).
public enum ProcessLiveness {
    /// Vrai si le processus existe. `kill(pid, 0)` n'envoie aucun signal ; EPERM signifie que le
    /// processus existe mais appartient à un autre utilisateur. Un pid ≤ 0 désignerait un groupe.
    public static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
