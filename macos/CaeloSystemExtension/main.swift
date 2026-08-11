import Foundation
import NetworkExtension

// A system extension is an executable, not a bundle the system instantiates a
// class from. It has to start itself and then stay alive: startSystemExtensionMode
// registers the provider named in Info.plist under NEProviderClasses, and
// dispatchMain hands the thread to the run loop so the process does not simply
// return and exit.
//
// This is the one piece iOS does not need — there the system loads an app
// extension and calls into it. Everything else about the tunnel is shared.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
