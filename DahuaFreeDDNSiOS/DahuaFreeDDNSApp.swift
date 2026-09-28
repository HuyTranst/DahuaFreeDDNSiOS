import SwiftUI
import UIKit

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: ContentView())
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

@_cdecl("main")
func main(argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.self))
}
