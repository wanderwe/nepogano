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

    // Той самий канал/метод, що android/.../MainActivity.kt слухає для
    // shareInstagramStory — lib/social_share.dart викликає його однаково
    // на обох платформах, різниться лише нативна реалізація.
    let channel = FlutterMethodChannel(
      name: "nepogano/social_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "shareInstagramStory":
        guard let args = call.arguments as? [String: Any],
          let filePath = args["filePath"] as? String
        else {
          result(false)
          return
        }
        result(AppDelegate.shareInstagramStory(filePath: filePath))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Пряма інтеграція Instagram Stories на iOS — публічний, задокументований
  /// механізм Meta (не потребує реєстрації розробника чи SDK): зображення
  /// кладеться на pasteboard під зарезервованим ключем, потім відкривається
  /// URL-схема instagram-stories://share — сам Instagram читає картинку
  /// з pasteboard після відкриття. Аналог Android-контракту
  /// com.instagram.share.ADD_TO_STORY в MainActivity.kt.
  private static func shareInstagramStory(filePath: String) -> Bool {
    guard let url = URL(string: "instagram-stories://share"),
      UIApplication.shared.canOpenURL(url),
      let imageData = FileManager.default.contents(atPath: filePath)
    else {
      return false
    }

    let pasteboardItems: [String: Any] = [
      "com.instagram.sharedSticker.backgroundImage": imageData
    ]
    // 5 хвилин — досить часу дійти до Instagram і повернутись, і не лишає
    // чиєсь фото на pasteboard назавжди.
    UIPasteboard.general.setItems(
      [pasteboardItems],
      options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
    )

    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }
}
