import Cocoa
import MetalKit

class RendererViewController: NSViewController {
    var renderer: Renderer!
    var scene: Scene!
    var gestureAmplification: Float = 0.02
    
    @IBOutlet weak var statusLabel: NSTextFieldCell!
    @IBOutlet weak var lensMenu: NSMenu!
    @IBOutlet weak var lensCell: NSPopUpButtonCell!
    
    var lensName: String = ""
    var numSurfaces: UInt32 = 0
    var focus: Float = 0
    var sensorScale: Float = 1
    var cameraScale: Float = 0.001
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice
        
        let lensURLs = Bundle.main.urls(forResourcesWithExtension: "len", subdirectory: "data/lenses")!
        for lensURL in lensURLs {
            let filename = String(lensURL.lastPathComponent.split(separator: ".").first!)
            lensMenu.items.append(NSMenuItem(title: filename, action: nil, keyEquivalent: ""))
        }
    }
    
    @IBAction func chooseLens(_ sender: Any) {
        loadLens(name: lensCell.selectedItem!.title)
    }
    
    private func loadLens(name: String) {
        lensCell.select(lensMenu.item(withTitle: name))
        
        let lensLoader = LensLoader()
        let lensURL = Bundle.main.url(forResource: name, withExtension: "len", subdirectory: "data/lenses")!
        let lens = lensLoader.load(lensURL, device: renderer.device)
        lensName = lens.name
        numSurfaces = lens.numSurfaces
        renderer.setLens(lens)
        
        updateStatus()
    }
    
    private func updateStatus() {
        let sensorSize = String(format: "%.1fx%.1f", sensorScale * 36, sensorScale * 24)
        statusLabel.title = """
        \(lensName)
        \(numSurfaces) surfaces
        Focus: \(focus)
        Sensor: \(sensorSize)
        Scale: \(cameraScale)
        """
        
        renderer.updateLens(focus, sensorScale, cameraScale)
    }
    
    func attach(scene: Scene) {
        let mtkView = self.view as! MTKView
        
        guard let newRenderer = Renderer(metalKitView: mtkView, scene: scene) else {
            fatalError("Renderer cannot be initialized")
        }

        renderer = newRenderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
        
        loadLens(name: "dgauss")
    }
    
    override func magnify(with event: NSEvent) {
        let zoom = float4x4([
            [ 1, 0, 0, 0 ],
            [ 0, 1, 0, 0 ],
            [ 0, 0, 1, -Float(event.magnification) * 100 * gestureAmplification ],
            [ 0, 0, 0, 1 ],
        ])
        renderer.updateProjection(by: zoom)
    }
    
    override func scrollWheel(with event: NSEvent) {
        if (event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0) {
            return
        }
        
        if (event.modifierFlags.contains(.shift)) {
            focus += Float(event.scrollingDeltaY) * 0.0005
            updateStatus()
            return
        }
        
        if (event.modifierFlags.contains(.control)) {
            cameraScale *= exp(0.0002 * Float(event.scrollingDeltaY))
            updateStatus()
            return
        }
        
        if (event.modifierFlags.contains(.command)) {
            sensorScale *= exp(0.0002 * Float(event.scrollingDeltaY))
            updateStatus()
            return
        }
        
        let shift = float4x4([
            [ 1, 0, 0, -Float(event.scrollingDeltaX) * 0.2 * gestureAmplification ],
            [ 0, 1, 0, Float(event.scrollingDeltaY) * 0.2 * gestureAmplification ],
            [ 0, 0, 1, 0 ],
            [ 0, 0, 0, 1 ]
        ])
        renderer.updateProjection(by: shift)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let radiansX = Float(event.deltaX) * Float.pi / 180
        let cX = cos(radiansX)
        let sX = sin(radiansX)
        let rotationX = float4x4([
            [ cX, 0, -sX, 0 ],
            [ 0, 1, 0, 0 ],
            [ sX, 0, cX, 0 ],
            [ 0, 0, 0, 1 ]
        ])
        
        let radiansY = Float(event.deltaY) * Float.pi / 180
        let cY = cos(radiansY)
        let sY = sin(radiansY)
        let rotationY = float4x4([
            [ 1, 0, 0, 0 ],
            [ 0, cY, sY, 0 ],
            [ 0, -sY, cY, 0 ],
            [ 0, 0, 0, 1 ]
        ])
        
        renderer.updateProjection(by: rotationX * rotationY)
    }
    
    override func rotate(with event: NSEvent) {
        let radians = event.rotation * Float.pi / 180
        let c = cos(radians)
        let s = sin(radians)
        let rotation = float4x4([
            [ c, s, 0, 0 ],
            [ -s, c, 0, 0 ],
            [ 0, 0, 1, 0 ],
            [ 0, 0, 0, 1 ]
        ])
        renderer.updateProjection(by: rotation)
    }
    
    @IBAction func saveFrame(_ sender: Any) {
        renderer.saveFrame()
    }
    
    @IBOutlet weak var samplingMethod: NSPopUpButton!
    @IBAction func selectSamplingMethod(_ sender: Any) {
        if let value = samplingMethod.selectedItem?.title {
            let options: [ String: SamplingMode ] = [
                "MIS":  .mis,
                "BSDF": .bsdf,
                "NEE":  .nee,
            ]
            
            if let option = options[value] {
                renderer.uniforms[0].samplingMode = option
                renderer.reset()
            }
        }
    }
}
