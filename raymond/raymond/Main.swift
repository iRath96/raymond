import Cocoa
import ArgumentParser
import Metal

@main
struct Raymond: ParsableCommand {

    @Argument(help: "Path to scene")
    var scenePath: String
    
    mutating func run() throws {
        let sceneURL = URL(filePath: scenePath)
        let scene = try SceneLoader().loadScene(fromURL: sceneURL, onDevice: MTLCreateSystemDefaultDevice()!)
        
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateInitialController() as! NSWindowController
        let viewController = windowController.contentViewController as! RendererViewController
        viewController.attach(scene: scene)
        
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
    
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}
