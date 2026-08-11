// What the extension needs from the core. The xcframework's own header, so
// there is one declaration of these functions rather than two that can drift.
#import "libcaelo.h"

#import <sys/ioctl.h>
#import <sys/socket.h>

// Finding the tunnel's own socket means asking the kernel about a control
// socket, and <sys/kern_control.h> is not in the iOS SDK — it ships with macOS
// only. The ABI is stable and public, so the three declarations that matter are
// reproduced here.
//
// wireguard-apple carries the same block for the same reason; see
// ATTRIBUTION.md. CTLIOCGINFO is written out because _IOWR needs the struct it
// is being defined alongside.
#define CTLIOCGINFO 0xc0644e03UL

struct ctl_info {
    u_int32_t ctl_id;
    char ctl_name[96];
};

struct sockaddr_ctl {
    u_char sc_len;
    u_char sc_family;
    u_int16_t ss_sysaddr;
    u_int32_t sc_id;
    u_int32_t sc_unit;
    u_int32_t sc_reserved[5];
};
