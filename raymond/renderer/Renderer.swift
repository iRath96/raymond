import Metal
import MetalKit
import MetalPerformanceShaders
import simd

fileprivate let log = SwiftLogger(named: "renderer")

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<DeviceUniforms>.size + 0xFF) & -0x100

enum RendererError: Error {
    case badVertexDescriptor
}

@objc class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var depthState: MTLDepthStencilState
    
    let pipelineState: MTLRenderPipelineState
    let rayGenerator: MTLComputePipelineState
    let imageNormalizer: MTLComputePipelineState
    let makeIndirectDispatch: MTLComputePipelineState
    
    let rayIntersector: MPSRayIntersector
    let shadowRayIntersector: MPSRayIntersector
    
    let inFlightSemaphore = DispatchSemaphore(value: 1)
    @objc var uniforms: UnsafeMutablePointer<DeviceUniforms>
    
    var frameIndex = UInt32(0)
    var rayCount = 0
    let maxDepth = 8
    
    var lensBuffer: MTLBuffer!
    var rayBuffer: MTLBuffer!
    var rayCountBuffer: MTLBuffer!
    var shadowRayBuffer: MTLBuffer!
    var shadowRayCountBuffer: MTLBuffer!
    var indirectDispatchBuffer: MTLBuffer!
    var intersectionBuffer: MTLBuffer!
    @objc var outputImageSize: MTLSize
    var outputImage: MTLTexture!
    @objc var normalizedImage: MTLTexture!
    
    var framesPerSecond: Float = 0
    var fpsSamples = 0
    
    var scene: Scene
    
    convenience init?(metalKitView: MTKView, scene: Scene) {
        self.init(device: metalKitView.device!, scene: scene)
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = .rgba16Float
        metalKitView.sampleCount = 1
        metalKitView.preferredFramesPerSecond = 120
        metalKitView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    }
    
    required init?(device: MTLDevice, scene: Scene) {
        self.scene = scene
        self.device = device
        
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize
        guard let buffer = self.device.makeBuffer(
            length: uniformBufferSize,
            options: .storageModeManaged
        ) else { return nil }
        
        self.dynamicUniformBuffer = buffer
        self.dynamicUniformBuffer.label = "UniformBuffer"
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to: DeviceUniforms.self, capacity: 1)
        uniforms[0] = DeviceUniforms(
            numLensSurfaces: 0,
            frameIndex: 0,
            lensSpectral: true,
            sensorScale: 1,
            cameraScale: 0.001,
            focus: 0,
            exposure: 1,
            stopIndex: 0,
            relativeStop: 1,
            numApertureBlades: 7,
            samplingMode: .mis)
        
        let lastHandlerConstants = MTLFunctionConstantValues()
        let ptr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        ptr.pointee = true
        lastHandlerConstants.setConstantValue(ptr, type: .bool, index: 0)
        ptr.deallocate()
        
        rayGenerator = Renderer.buildComputePipelineWithDevice(library: scene.library, name: "generateRays")!
        imageNormalizer = Renderer.buildComputePipelineWithDevice(library: scene.library, name: "normalizeImage")!
        makeIndirectDispatch = Renderer.buildComputePipelineWithDevice(library: scene.library, name: "makeIndirectDispatchArguments")!
        
        do {
            pipelineState = try Renderer.buildBlitPipelineWithDevice(library: scene.library)
        } catch {
            log.error("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        rayIntersector = MPSRayIntersector(device: device)
        shadowRayIntersector = MPSRayIntersector(device: device)
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDescriptor) else { return nil }
        depthState = state
        
        outputImageSize = MTLSizeMake(0, 0, 1)
        lensBuffer = device.makeBuffer(length: 100) /// @todo hack
        
        super.init()
        
        self.setupRayIntersectors()
    }
    
    private func setupRayIntersectors() {
        rayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        rayIntersector.rayStride = MemoryLayout<DeviceRay>.stride
        rayIntersector.intersectionDataType = .distancePrimitiveIndexInstanceIndexCoordinates
        rayIntersector.intersectionStride = MemoryLayout<DeviceIntersection>.stride
        
        shadowRayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        shadowRayIntersector.rayStride = MemoryLayout<DeviceShadowRay>.stride
        shadowRayIntersector.intersectionDataType = .distance
        shadowRayIntersector.intersectionStride = MemoryLayout<DeviceIntersection>.stride
    }
    
    class func buildComputePipelineWithDevice(
        library: MTLLibrary,
        name: String,
        constantValues: MTLFunctionConstantValues = MTLFunctionConstantValues(),
        linkedFunctions: MTLLinkedFunctions? = nil
    ) -> MTLComputePipelineState? {
        do {
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = try library.makeFunction(name: name, constantValues: constantValues)
            descriptor.label = name
            descriptor.linkedFunctions = linkedFunctions
            return try library.device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        } catch {
            log.error("Unable to compile compute pipeline state. Error info: \(error)")
            return nil
        }
    }
    
    class func buildBlitPipelineWithDevice(library: MTLLibrary) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let vertexFunction = library.makeFunction(name: "blitVertex")
        let fragmentFunction = library.makeFunction(name: "blitFragment")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "BlitPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // .rgba16Float
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        //pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        return try library.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents())
            .bindMemory(to: DeviceUniforms.self, capacity: 1)
    }
    
    private func updateState() {
        /// Update any state before rendering
        uniforms[0].frameIndex = frameIndex
        frameIndex += 1
    }
    
    @objc func execute(in commandBuffer: MTLCommandBuffer) {
        let semaphore = inFlightSemaphore
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        
        self.updateDynamicBufferState()
        self.updateState()
        
        if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
            computeEncoder.label = "Clear Ray Count"
            computeEncoder.fill(
                buffer: rayCountBuffer, range: 0..<rayCountBuffer.length,
                value: 0)
            computeEncoder.endEncoding()
        }
        
        if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
            computeEncoder.label = "Clear Shadow Ray Count"
            computeEncoder.fill(buffer: shadowRayCountBuffer!, range: 0..<shadowRayCountBuffer!.length, value: 0)
            computeEncoder.endEncoding()
        }
        
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = "Primary Ray Generation"
            computeEncoder.setComputePipelineState(rayGenerator)
            computeEncoder.setBuffer(
                rayBuffer, offset: 0,
                index: GeneratorBufferIndex.rays.rawValue)
            computeEncoder.setBuffer(
                rayCountBuffer, offset: 0,
                index: GeneratorBufferIndex.rayCount.rawValue)
            computeEncoder.setBuffer(
                dynamicUniformBuffer,
                offset: 0,
                index: GeneratorBufferIndex.uniforms.rawValue)
            computeEncoder.setBuffer(
                scene.contextBuffer,
                offset: 0,
                index: GeneratorBufferIndex.context.rawValue)
            computeEncoder.setBuffer(
                lensBuffer,
                offset: 0,
                index: GeneratorBufferIndex.lens.rawValue)
            computeEncoder.dispatchThreads(
                outputImageSize,
                threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            computeEncoder.endEncoding()
        }
        
        var currentRayBufferOffset = 0
        var nextRayBufferOffset = rayBuffer.length / 2
        
        for depth in 0..<maxDepth {
            let rayCountBufferOffset = depth * MemoryLayout<UInt32>.stride
            let isMaxDepth = (depth+1 == maxDepth)
            
            rayIntersector.encodeIntersection(
                commandBuffer: commandBuffer,
                intersectionType: .nearest,
                rayBuffer: rayBuffer,
                rayBufferOffset: currentRayBufferOffset,
                intersectionBuffer: intersectionBuffer,
                intersectionBufferOffset: 0,
                rayCountBuffer: rayCountBuffer,
                rayCountBufferOffset: rayCountBufferOffset,
                accelerationStructure: scene.accelerationStructure)
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.label = "Ordinary Indirect Dispatch"
                computeEncoder.setComputePipelineState(makeIndirectDispatch)
                computeEncoder.setBuffer(rayCountBuffer, offset: rayCountBufferOffset, index: 0)
                computeEncoder.setBuffer(indirectDispatchBuffer, offset: 0, index: 1)
                computeEncoder.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
                computeEncoder.endEncoding()
            }
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.label = "Shade Rays and Secondary Ray Generation"
                computeEncoder.setTexture(outputImage, index: 0)
                computeEncoder.setComputePipelineState(scene.intersectionHandler)
                
                // ray buffers
                computeEncoder.setBuffer(
                    intersectionBuffer, offset: 0,
                    index: ShadingBufferIndex.intersections.rawValue)
                computeEncoder.setBuffer(
                    rayBuffer, offset: currentRayBufferOffset,
                    index: ShadingBufferIndex.rays.rawValue)
                computeEncoder.setBuffer(
                    rayBuffer, offset: nextRayBufferOffset,
                    index: ShadingBufferIndex.nextRays.rawValue)
                computeEncoder.setBuffer(
                    shadowRayBuffer, offset: 0,
                    index: ShadingBufferIndex.shadowRays.rawValue)
                
                // ray counters
                computeEncoder.setBuffer(
                    rayCountBuffer,
                    offset: rayCountBufferOffset, index: ShadingBufferIndex.currentRayCount.rawValue)
                computeEncoder.setBuffer(
                    rayCountBuffer,
                    offset: rayCountBufferOffset + MemoryLayout<UInt32>.stride, index: ShadingBufferIndex.nextRayCount.rawValue)
                computeEncoder.setBuffer(
                    shadowRayCountBuffer, offset: rayCountBufferOffset,
                    index: ShadingBufferIndex.shadowRayCount.rawValue)
                
                // scene buffers
                computeEncoder.setBuffer(
                    dynamicUniformBuffer,
                    offset: 0, index: ShadingBufferIndex.uniforms.rawValue)
                
                // shader table
                computeEncoder.setBuffer(
                    scene.contextBuffer, offset: 0,
                    index: ShadingBufferIndex.context.rawValue)
                computeEncoder.useResources(
                    scene.resourcesRead, usage: .read)
                
                computeEncoder.dispatchThreadgroups(
                    indirectBuffer: indirectDispatchBuffer,
                    indirectBufferOffset: 0,
                    threadsPerThreadgroup: MTLSizeMake(64, 1, 1))
                computeEncoder.endEncoding()
            }
            
            if isMaxDepth {
                break
            }
            
            shadowRayIntersector.encodeIntersection(
                commandBuffer: commandBuffer,
                intersectionType: .any,
                rayBuffer: shadowRayBuffer!,
                rayBufferOffset: 0,
                intersectionBuffer: intersectionBuffer!,
                intersectionBufferOffset: 0,
                rayCountBuffer: shadowRayCountBuffer!,
                rayCountBufferOffset: depth * MemoryLayout<UInt32>.stride,
                accelerationStructure: scene.accelerationStructure)
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.label = "Shadow Indirect Dispatch"
                computeEncoder.setComputePipelineState(makeIndirectDispatch)
                computeEncoder.setBuffer(shadowRayCountBuffer, offset: rayCountBufferOffset, index: 0)
                computeEncoder.setBuffer(indirectDispatchBuffer, offset: 0, index: 1)
                computeEncoder.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
                computeEncoder.endEncoding()
            }
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.label = "Shade Shadow Rays"
                computeEncoder.setTexture(outputImage, index: 0)
                computeEncoder.setComputePipelineState(scene.shadowRayHandler)
                computeEncoder.setBuffer(intersectionBuffer, offset: 0, index: ShadowBufferIndex.intersections.rawValue)
                computeEncoder.setBuffer(shadowRayBuffer, offset: 0, index: ShadowBufferIndex.shadowRays.rawValue)
                computeEncoder.setBuffer(shadowRayCountBuffer, offset: rayCountBufferOffset, index: ShadowBufferIndex.rayCount.rawValue)
                computeEncoder.setBuffer(
                    scene.contextBuffer, offset: 0,
                    index: ShadingBufferIndex.context.rawValue)
                computeEncoder.useResources(
                    scene.resourcesRead, usage: .read)
                computeEncoder.dispatchThreadgroups(
                    indirectBuffer: indirectDispatchBuffer!,
                    indirectBufferOffset: 0,
                    threadsPerThreadgroup: MTLSizeMake(64, 1, 1))
                computeEncoder.endEncoding()
            }
            
            // ping pong
            (currentRayBufferOffset, nextRayBufferOffset) = (nextRayBufferOffset, currentRayBufferOffset)
        }
        
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = "Normalize output image"
            computeEncoder.setTexture(outputImage, index: 0)
            computeEncoder.setTexture(normalizedImage, index: 1)
            computeEncoder.setBuffer(dynamicUniformBuffer, offset: 0, index: 0)
            computeEncoder.setComputePipelineState(imageNormalizer)
            computeEncoder.dispatchThreads(outputImageSize, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            computeEncoder.endEncoding()
        }
        
        commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
            semaphore.signal()
        }
    }
    
    @objc func draw(encoder renderEncoder: MTLRenderCommandEncoder) {
        /// Final pass rendering code here
        renderEncoder.label = "Blit Render"
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(outputImage, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let frameStart = Date()
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
                let frameTime = -Float(frameStart.timeIntervalSinceNow)
                if frameTime > 1.0 {
                    log.warn("frame took more than \(frameTime) seconds. Sleeping 3 seconds to not lock up system!")
                    sleep(3)
                }
                
                self.framesPerSecond += 1/frameTime
                self.fpsSamples += 1
                
                if self.fpsSamples >= 10 {
                    let fps = self.framesPerSecond / Float(self.fpsSamples)
                    let width = self.outputImageSize.width
                    let height = self.outputImageSize.height
                    
                    let rayCount = self.rayStatistics()
                    
                    DispatchQueue.main.async {
                        view.window?.title = String(format: "FPS: %.1f at %dx%d [%d frames] %.1f Mray/s",
                            fps, width, height, self.frameIndex,
                            Float(rayCount) / frameTime * 1e-6
                        )
                    }
                    
                    self.framesPerSecond = 0
                    self.fpsSamples = 0
                }
                
                semaphore.signal()
            }
            
            self.execute(in: commandBuffer)
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                draw(encoder: renderEncoder)
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    drawable.layer.wantsExtendedDynamicRangeContent = true
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    private func rayStatistics() -> Int {
        let counts = rayCountBuffer.contents().bindMemory(to: UInt32.self, capacity: maxDepth)
        let shadowCounts = shadowRayCountBuffer!.contents().bindMemory(to: UInt32.self, capacity: maxDepth)
        var totalRayCount = 0
        
        for depth in 0..<maxDepth {
            totalRayCount += Int(counts[depth] + shadowCounts[depth])
            //print(depth, counts[depth], shadowCounts[depth])
        }
        //print("total", totalRayCount)
        //print()
        
        return totalRayCount
    }
    
    private func makeOutputImage() {
        let outputImageDescriptor = MTLTextureDescriptor()
        outputImageDescriptor.pixelFormat = .rgba32Float
        outputImageDescriptor.width = outputImageSize.width
        outputImageDescriptor.height = outputImageSize.height
        outputImageDescriptor.usage = [ .shaderRead, .shaderWrite ]
        outputImageDescriptor.storageMode = .shared
        
        outputImage = device.makeTexture(descriptor: outputImageDescriptor)!
        outputImage.label = "Output image"
        
        normalizedImage = device.makeTexture(descriptor: outputImageDescriptor)!
        normalizedImage.label = "Normalized output image"
    }
    
    @objc func reset() {
        frameIndex = 0
        makeOutputImage()
    }
    
    func setExposure(_ exposure: Float) {
        uniforms[0].exposure = exposure
    }
    
    @objc func setLens(_ lens: Lens?) {
        guard let lens = lens else {
            uniforms[0].numLensSurfaces = 0
            return
        }
        
        self.lensBuffer = lens.buffer
        uniforms[0].numLensSurfaces = lens.numSurfaces
    }
    
    func updateLens(_ focus: Float, _ sensorScale: Float, _ cameraScale: Float) {
        uniforms[0].focus = focus
        uniforms[0].sensorScale = sensorScale
        uniforms[0].cameraScale = cameraScale
        
        reset()
    }
    
    @objc func updateProjection(by multiplying: float4x4) {
        var camera = scene.camera
        camera.transform = camera.transform * multiplying.transpose
        scene.camera = camera
        
        reset()
    }
    
    @objc func setSize(width: Int, height: Int) {
        if outputImageSize.width == width && outputImageSize.height == height {
            /// no need to resize
            return
        }
        
        outputImageSize = MTLSizeMake(width, height, 1)
        
        rayCount = outputImageSize.width * outputImageSize.height
        rayBuffer = device.makeBuffer(
            type: DeviceRay.self,
            count: 2 * rayCount,
            options: .storageModePrivate)
        shadowRayBuffer = device.makeBuffer(
            type: DeviceShadowRay.self,
            count: rayCount,
            options: .storageModePrivate)
        rayCountBuffer = device.makeBuffer(
            type: UInt32.self,
            count: maxDepth + 1,
            options: .storageModeShared)
        shadowRayCountBuffer = device.makeBuffer(
            type: UInt32.self,
            count: maxDepth,
            options: .storageModeShared)
        intersectionBuffer = device.makeBuffer(
            type: DeviceIntersection.self,
            count: rayCount,
            options: .storageModePrivate)
        indirectDispatchBuffer = device.makeBuffer(
            type: MTLDispatchThreadgroupsIndirectArguments.self,
            count: 1,
            options: .storageModePrivate)
        
        rayBuffer.label = "Rays"
        shadowRayBuffer!.label = "Shadow rays"
        intersectionBuffer.label = "Intersections"
        
        reset()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setSize(width: Int(size.width), height: Int(size.height))
    }
    
    func saveFrame() {
        let path = URL.desktopDirectory.appending(path: "frame.exr")
        outputImage.saveEXR(at: path, normalizedBy: 1 / Float(frameIndex))
    }
}