import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    // Limpiar badge cuando la escena pasa a activa en iOS 13+
    AppDelegate.clearBadgeCount()
  }
}

