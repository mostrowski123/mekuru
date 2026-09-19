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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerStorageChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// `mekuru/ios_storage`: keeps re-downloadable data (MeCab dictionaries,
  /// KanjiVG) out of iCloud/device backups, which App Review requires.
  private func registerStorageChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "mekuru/ios_storage", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "excludeFromBackup", let paths = call.arguments as? [String] else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          for path in paths {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
          }
          result(nil)
        } catch {
          result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
        }
      }
  }
}
