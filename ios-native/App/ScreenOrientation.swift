import UIKit
@MainActor enum ScreenOrientation {
    static var mask:UIInterfaceOrientationMask = .portrait
    static var windowScene:UIWindowScene? { UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where:{ $0.activationState == .foregroundActive }) }
    static func select(_ mask:UIInterfaceOrientationMask,onError:@escaping (String)->Void) {
        self.mask=mask
        guard let scene=windowScene else { return }
        var controller=scene.keyWindow?.rootViewController
        while let presented=controller?.presentedViewController { controller=presented }
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations:mask)) { error in
            Task { @MainActor in onError("暂时无法切换，请关闭系统方向锁定后重试。\n\(error.localizedDescription)") }
        }
    }
}
@MainActor final class MobileAppDelegate:NSObject,UIApplicationDelegate {
    func application(_ application:UIApplication,supportedInterfaceOrientationsFor window:UIWindow?)->UIInterfaceOrientationMask { ScreenOrientation.mask }
}
