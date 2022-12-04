import Cocoa
import ArgumentParser
import Metal

@main
struct Raymond: ParsableCommand {

    @Argument(help: "Path to scene")
    var scenePath: String
    
    @Option(name: .short, help: "Gesture amplification")
    var gestureAmplification: Float = 0.02
    
    @Flag(name: .shortAndLong, help: ArgumentHelp(
        "Compile shaders using xcrun",
        discussion: "Enables better profiling information in Xcode"
    ))
    var externalCompile = false
    
    mutating func run() throws {
        /*var sceneLoader = SceneLoader()
        sceneLoader.externalCompile = externalCompile
        
        let sceneURL = URL(filePath: scenePath)
        let scene = try sceneLoader.loadScene(fromURL: sceneURL, onDevice: MTLCreateSystemDefaultDevice()!)
        
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateInitialController() as! NSWindowController
        let viewController = windowController.contentViewController as! RendererViewController
        viewController.gestureAmplification = gestureAmplification
        viewController.attach(scene: scene)
        
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()*/
        
        //let glassURLs = Bundle.main.urls(forResourcesWithExtension: "glc", subdirectory: "data/glass")!
        let glassURLs = ["schott", "obsolete001", "hoya"].map {
            Bundle.main.url(forResource: $0, withExtension: "glc", subdirectory: "data/glass")!
        }
        let lensLoader = LensLoader()
        for glassURL in glassURLs {
            let numGlasses = lensLoader.loadGlassCatalog(glassURL)
            print("loaded \(numGlasses) from \(glassURL.lastPathComponent)")
        }
        
        launchUI()
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
