import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        if NSClassFromString("XCTestCase") != nil {
            window.rootViewController = UIViewController()
        } else {
            #if targetEnvironment(macCatalyst)
                window.rootViewController = MacGameController()
                scene.sizeRestrictions?.minimumSize = CGSize(width: 960, height: 540)
                scene.title = "X Arcana"
            #else
                window.rootViewController = WandController()
            #endif
        }
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        #if !targetEnvironment(macCatalyst)
            UIApplication.shared.isIdleTimerDisabled = true
            ControllerSession.shared.start()
        #endif
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        #if !targetEnvironment(macCatalyst)
            UIApplication.shared.isIdleTimerDisabled = false
            ControllerSession.shared.stop()
        #endif
    }
}
