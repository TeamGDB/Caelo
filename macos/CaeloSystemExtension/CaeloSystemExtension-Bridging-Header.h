// What the extension needs from the core. The xcframework's own header, so
// there is one declaration of these functions rather than two that can drift.
#import "libcaelo.h"

#import <sys/ioctl.h>
#import <sys/kern_control.h>
#import <sys/socket.h>
#import <sys/sys_domain.h>
