//
//  GameViewController.swift
//  raymond macOS
//
//  Created by Alexander Rath on 16.11.21.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
    }
    
    override func magnify(with event: NSEvent) {
        let zoom = float4x4([
            [ 1, 0, 0, 0 ],
            [ 0, 1, 0, 0 ],
            [ 0, 0, 1, -Float(event.magnification) * 100 ],
            [ 0, 0, 0, 1 ],
        ])
        renderer.updateProjection(by: zoom)
    }
    
    override func scrollWheel(with event: NSEvent) {
        if (event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0) {
            return
        }
        
        let shift = float4x4([
            [ 1, 0, 0, -Float(event.scrollingDeltaX) * 0.2 ],
            [ 0, 1, 0, Float(event.scrollingDeltaY) * 0.2 ],
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
}
