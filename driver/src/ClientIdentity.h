#ifndef EQ_CLIENT_IDENTITY_H
#define EQ_CLIENT_IDENTITY_H
#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <stdbool.h>
#include <string.h>

// Both paths read kernel credentials for the host-supplied PID. Never trust a
// UID supplied by a property payload, filename or file owner alone. Some audio
// host sandboxes expose BSD process metadata through sysctl but not libproc.
static inline bool EQClientUID(pid_t pid, uid_t *uid) {
    if (pid <= 0 || uid == NULL) { return false; }
    struct proc_bsdinfo process;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, sizeof(process)) == sizeof(process)) {
        *uid = process.pbi_uid;
        return true;
    }
    int name[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(name, 4, &info, &size, NULL, 0) != 0 || size != sizeof(info) ||
        info.kp_proc.p_pid != pid) { return false; }
    *uid = info.kp_eproc.e_ucred.cr_uid;
    return true;
}
#endif
