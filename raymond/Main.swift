import Cocoa
import ArgumentParser
import Metal

fileprivate let log = SwiftLogger(named: "raymond")

@main
struct Raymond: ParsableCommand {

    @Argument(help: "Path to scene")
    var scenePath: String
    
    @Flag(name: .shortAndLong, help: ArgumentHelp(
        "Compile shaders using xcrun",
        discussion: "Enables better profiling information in Xcode"
    ))
    var externalCompile = false
    
    mutating func run() throws {
        log.info("Welcome to raymond")
        
        let device = MTLCreateSystemDefaultDevice()!
        let printfBuffer = PrintfBuffer(on: device, sized: 1024 * 1024)
        
        var sceneLoader = SceneLoader()
        sceneLoader.externalCompile = externalCompile
        
        let sceneURL = URL(filePath: scenePath)
        let scene = try sceneLoader.loadScene(
            fromURL: sceneURL,
            onDevice: MTLCreateSystemDefaultDevice()!,
            constants: printfBuffer.constants)
        let renderer = Renderer(device: device, printfBuffer: printfBuffer, scene: scene)!
        
        //let glassURLs = Bundle.main.urls(forResourcesWithExtension: "glc", subdirectory: "data/glass")!
        let glassURLs = ["schott", "obsolete001", "hoya"].map {
            Bundle.main.url(forResource: $0, withExtension: "glc", subdirectory: "data/glass")!
        }
        let lensLoader = LensLoader()
        _ = glassURLs.map(lensLoader.loadGlassCatalog)
        
        launchUI(with: renderer)
    }
    
    private func launchUI(with renderer: Renderer) {
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
