# platform/apple

Swift shared by the iOS packet tunnel extension and the macOS system extension.

The two run in different kinds of process — iOS embeds an app extension, macOS
installs a system extension — but what happens inside is the same: ask the core
to describe the configuration, tell the system what the tunnel looks like, hand
the descriptor over.

It lives here rather than in either Xcode project because both reference it.
Two copies of a file this fiddly would disagree within a week, and the one that
disagreed would be whichever platform was tested less.
