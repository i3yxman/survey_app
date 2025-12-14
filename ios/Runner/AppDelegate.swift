// ios/Runner/AppDelegate.swift

import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 1) 通知代理（前台展示用）
    UNUserNotificationCenter.current().delegate = self

    // 2) 请求通知权限 + 注册远程通知（拿 APNs token）
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted, error in
      DispatchQueue.main.async {
        // 不管 granted 与否都可以调用注册；没权限系统也不会给你展示
        UIApplication.shared.registerForRemoteNotifications()
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 前台也展示（你原来这段保留）
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  // ✅ 可选但强烈建议：打印 APNs token（用于验证“APNs 是否真的注册成功”）
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
    let token = tokenParts.joined()
    print("✅ APNs deviceToken =", token, "len=", token.count)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ APNs register failed:", error)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
