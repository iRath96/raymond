import Cocoa
import ArgumentParser
import Metal

fileprivate let log = Logger(named: "raymond")

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
        log.info("Welcome to raymond")
        
        var sceneLoader = SceneLoader()
        sceneLoader.externalCompile = externalCompile
        
        let sceneURL = URL(filePath: scenePath)
        let scene = try sceneLoader.loadScene(fromURL: sceneURL, onDevice: MTLCreateSystemDefaultDevice()!)
        let renderer = Renderer(device: MTLCreateSystemDefaultDevice()!, scene: scene)!
        
        //let glassURLs = Bundle.main.urls(forResourcesWithExtension: "glc", subdirectory: "data/glass")!
        let glassURLs = ["schott", "obsolete001", "hoya"].map {
            Bundle.main.url(forResource: $0, withExtension: "glc", subdirectory: "data/glass")!
        }
        let lensLoader = LensLoader()
        _ = glassURLs.map(lensLoader.loadGlassCatalog)
        
        let lensURL = Bundle.main.url(forResource: "dgauss", withExtension: "len", subdirectory: "data/lenses")!
        let lens = lensLoader.load(lensURL, device: renderer.device)
        renderer.setLens(lens)
        
        let rootViewController = AppViewController(renderer: renderer)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [ .titled, .closable, .resizable, .miniaturizable ],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = rootViewController
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        var cchar: UnsafeMutablePointer<CChar>?
        _ = NSApplicationMain(0, &cchar)
    }
    
}
