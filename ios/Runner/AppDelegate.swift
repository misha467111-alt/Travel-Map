import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "travel_map/native_config",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { call, result in
                guard call.method == "configureGoogleMaps",
                      let args = call.arguments as? [String: Any],
                      let apiKey = args["apiKey"] as? String,
                      !apiKey.isEmpty else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                GMSServices.provideAPIKey(apiKey)
                result(nil)
            }
        }

        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }
}
