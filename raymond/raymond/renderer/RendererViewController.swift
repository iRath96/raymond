import Cocoa
import MetalKit

class RendererViewController: NSViewController {
    var renderer: Renderer!
    var scene: Scene!
    var gestureAmplification: Float = 0.02
    
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
    }
    
    func attach(scene: Scene) {
        let mtkView = self.view as! MTKView
        
        guard let newRenderer = Renderer(metalKitView: mtkView, scene: scene) else {
            fatalError("Renderer cannot be initialized")
        }

        renderer = newRenderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
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
