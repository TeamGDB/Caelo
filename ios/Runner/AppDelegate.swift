import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Held for the app's lifetime: it owns the channel and observes VPN status
  /// changes, and a manager that is collected stops reporting them.
  private var vpn: VpnManager?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Through a registrar rather than off the bridge directly: the bridge
    // vends a plugin registry, and a messenger is what a registrar is for.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CaeloVpn") {
      vpn = VpnManager(messenger: registrar.messenger())
    }
  }
}
