import SwiftUI
import UIKit

@MainActor @Observable final class PhoneQuickActionCoordinator {
  static let shared = PhoneQuickActionCoordinator()
  static let projectActionType = "com.cseibert.StageChasePhone.open-project"
  static let projectIDKey = "projectID"
  static let maximumProjectActions = 4

  var pendingProjectID: UUID?

  func update(projects: [Project]) {
    if let data = try? JSONEncoder().encode(projects.map {
      SharedPhotoProject(id: $0.id, name: $0.name)
    }) {
      UserDefaults(suiteName: SharedPhotoIntake.appGroup)?.set(
        data, forKey: SharedPhotoIntake.projectsKey)
    }
    UIApplication.shared.shortcutItems = Array(projects.prefix(Self.maximumProjectActions)).map {
      project in
      UIApplicationShortcutItem(
        type: Self.projectActionType,
        localizedTitle: project.name,
        localizedSubtitle: nil,
        icon: nil,
        userInfo: [Self.projectIDKey: project.id.uuidString as NSString])
    }
  }

  func receive(_ shortcutItem: UIApplicationShortcutItem?) {
    guard let shortcutItem,
      shortcutItem.type == Self.projectActionType,
      let rawID = shortcutItem.userInfo?[Self.projectIDKey] as? String,
      let projectID = UUID(uuidString: rawID)
    else { return }
    pendingProjectID = projectID
  }
}

@MainActor final class StageChasePhoneAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = StageChasePhoneSceneDelegate.self
    return configuration
  }

}

@MainActor final class StageChasePhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    PhoneQuickActionCoordinator.shared.receive(connectionOptions.shortcutItem)
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    PhoneQuickActionCoordinator.shared.receive(shortcutItem)
    completionHandler(shortcutItem.type == PhoneQuickActionCoordinator.projectActionType)
  }
}

@main struct StageChasePhoneApp: App {
  @UIApplicationDelegateAdaptor(StageChasePhoneAppDelegate.self) private var appDelegate
  @State private var model = AppModel()
  @AppStorage("appearancePreference") private var appearancePreference =
    AppAppearancePreference.system.rawValue
  var body: some Scene {
    WindowGroup {
      RootView().environment(model).tint(.indigo).preferredColorScheme(
        AppAppearancePreference(rawValue: appearancePreference)?.colorScheme)
    }
  }
}
