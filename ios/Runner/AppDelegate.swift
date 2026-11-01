import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // let the notifications plugin handle banners while the app is open
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // Ask iOS for an APNs token explicitly. Without it FCM never gets one and
    // getToken() fails with apns-token-not-set.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // needed so background notification isolates can reach the plugins too
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // real Liquid Glass surface (UIGlassEffect) exposed to Dart as a platform view
    engineBridge.pluginRegistry.registrar(forPlugin: "KindredGlass")?
      .register(KindredGlassFactory(), withId: "kindred/glass")
  }
}

// Native Liquid Glass. iOS 26 renders Apple's real UIGlassEffect; older iOS gets
// a material blur so the bar still reads correctly.
final class KindredGlassFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    KindredGlassView(frame: frame)
  }
}

final class KindredGlassView: NSObject, FlutterPlatformView {
  private let container = UIView()

  init(frame: CGRect) {
    super.init()
    container.frame = frame
    container.backgroundColor = .clear
    container.layer.cornerRadius = 24
    container.layer.cornerCurve = .continuous
    container.clipsToBounds = true

    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      effect = UIBlurEffect(style: .systemThinMaterial)
    }
    let blur = UIVisualEffectView(effect: effect)
    blur.frame = container.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(blur)
  }

  func view() -> UIView { container }
}
