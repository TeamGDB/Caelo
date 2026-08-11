// What the tunnel extension needs from C, on both Apple platforms.
//
// Shared for the same reason the provider is: two copies of this would drift,
// and the drift would only show up on whichever platform was tested less. That
// already happened once — the iOS copy declared these by hand and the macOS one
// included the system header, and Swift could not see CTLIOCGINFO on macOS
// because there it is a function-like macro, which Swift does not import.

// The core. Each platform points HEADER_SEARCH_PATHS at its own build of this,
// so there is one declaration of these functions rather than two.
#import "libcaelo.h"

#import <sys/ioctl.h>
#import <sys/socket.h>

// Finding the tunnel's own socket means asking the kernel about a control
// socket. <sys/kern_control.h> is not in the iOS SDK at all, and on macOS the
// constant it defines is a macro Swift cannot import — so the three things that
// matter are declared here, identically for both. The ABI is public and stable.
//
// wireguard-apple carries the same block for the same reasons; see
// ATTRIBUTION.md.
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
