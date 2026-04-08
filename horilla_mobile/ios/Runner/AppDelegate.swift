import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let deviceInfoChannelName = "horilla/device_info"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: deviceInfoChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getDeviceInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.buildDeviceInfoPayload())
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func buildDeviceInfoPayload() -> [String: String] {
    let device = UIDevice.current
    let modelIdentifier = Self.deviceModelIdentifier()
    let osVersion = "iOS \(device.systemVersion)"

    return [
      "manufacturer": "Apple",
      "model": modelIdentifier,
      "osVersion": osVersion,
      "deviceName": device.name,
    ]
  }

  private static func deviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)

    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce(into: "") { partialResult, element in
      guard let value = element.value as? Int8, value != 0 else {
        return
      }
      partialResult.append(String(UnicodeScalar(UInt8(value))))
    }

    return identifier.isEmpty ? UIDevice.current.model : identifier
  }
}
