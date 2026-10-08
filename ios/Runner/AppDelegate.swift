import UIKit
import Flutter

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

    if let shareRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "SharePlugin") {
      SharePlugin.register(with: shareRegistrar)
    }

    let SYSTEM_CHANNEL = FlutterMethodChannel(name: "mobile.lichess.org/system",
                                                    binaryMessenger: engineBridge.applicationRegistrar.messenger())

    SYSTEM_CHANNEL.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard call.method == "getTotalRam" else {
        result(FlutterMethodNotImplemented)
        return
      }

      result(self.getPhysicalMemory())
    })
  }

  private func getPhysicalMemory() -> Int {
    let memory : Int = Int(ProcessInfo.processInfo.physicalMemory)
    let constant : Int = 1_048_576
    let res = memory / constant
    return Int(res)
  }
}
