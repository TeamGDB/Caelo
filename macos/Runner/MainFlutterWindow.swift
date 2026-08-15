import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var vpn: VpnManager?
  private var updater: Updater?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Let the content run all the way up behind the traffic lights.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true

    // One button and two lines of text do not need much room, but they do need
    // enough that the layout never has to fight for it.
    self.minSize = NSSize(width: 420, height: 520)

    // The window chrome cannot follow the system setting, because the app's
    // scheme does not: someone running a light interface on a dark system would
    // otherwise get a dark title bar over a light window, which reads as a
    // rendering bug rather than a preference. Flutter owns the palette, so
    // Flutter is asked.
    let channel = FlutterMethodChannel(
      name: "team.gdb.caelo/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setBrightness",
            let brightness = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.apply(brightness: brightness)
      result(nil)
    }

    // Dark until told otherwise. The first frame arrives before Dart has read
    // the stored preference, and a flash of white is worse than a flash of
    // black in an app that is usually dark.
    self.apply(brightness: "dark")

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Held for the window's lifetime: it owns the channel and observes VPN
    // status changes, and a manager that is collected stops reporting them.
    vpn = VpnManager(messenger: flutterViewController.engine.binaryMessenger)

    // Also held for the window's lifetime. Sparkle's controller schedules its
    // own work; one that is collected stops checking, silently.
    updater = Updater(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Matches the window chrome to the palette Flutter is painting with.
  ///
  /// The background colour matters even though Flutter covers it: it is what
  /// shows during a live resize, before the engine has produced a frame at the
  /// new size.
  private func apply(brightness: String) {
    let light = brightness == "light"
    self.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    self.backgroundColor = light
      ? NSColor(red: 0xD7 / 255, green: 0xE7 / 255, blue: 0xE1 / 255, alpha: 1)
      : NSColor(red: 0x09 / 255, green: 0x0B / 255, blue: 0x0E / 255, alpha: 1)
  }
}
