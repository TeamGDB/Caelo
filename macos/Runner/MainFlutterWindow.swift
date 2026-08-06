import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The interface is dark only, so the window chrome is forced to match
    // rather than following the system setting — a light title bar above a
    // black window looks like a rendering bug.
    self.appearance = NSAppearance(named: .darkAqua)

    // Let the black content run all the way up behind the traffic lights.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.backgroundColor = NSColor.black
    self.isMovableByWindowBackground = true

    // One button and two lines of text do not need much room, but they do need
    // enough that the layout never has to fight for it.
    self.minSize = NSSize(width: 420, height: 520)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
