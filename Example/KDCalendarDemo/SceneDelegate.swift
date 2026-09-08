import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let classic = ClassicDemoViewController()
        classic.tabBarItem = UITabBarItem(title: "Classic", image: UIImage(systemName: "calendar"), tag: 0)

        let plain = DefaultStyleDemoViewController()
        plain.tabBarItem = UITabBarItem(title: "Default", image: UIImage(systemName: "calendar.badge.clock"), tag: 1)

        let swiftUI = UIHostingController(rootView: SwiftUIDemoView())
        swiftUI.tabBarItem = UITabBarItem(title: "SwiftUI", image: UIImage(systemName: "swift"), tag: 2)

        let tabs = UITabBarController()
        tabs.viewControllers = [classic, plain, swiftUI]
        tabs.selectedIndex = DemoArguments.initialTab

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Launch arguments used for screenshots and UI checks:
/// `-tab N` opens the Nth tab, `-sampleEvents` seeds events without touching the system calendar.
enum DemoArguments {
    static var initialTab: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count else { return 0 }
        return Int(arguments[index + 1]) ?? 0
    }

    static var usesSampleEvents: Bool {
        ProcessInfo.processInfo.arguments.contains("-sampleEvents")
    }
}
