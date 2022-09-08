import Metal
import MetalKit
import MetalPerformanceShaders
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var depthState: MTLDepthStencilState
    
    let pipelineState: MTLRenderPipelineState
    let rayGenerator: MTLComputePipelineState
    let makeIndirectDispatch: MTLComputePipelineState
    
    let rayIntersector: MPSRayIntersector
    
    let inFlightSemaphore = DispatchSemaphore(value: 1)
    var uniforms: UnsafeMutablePointer<Uniforms>
    
    var projectionMatrix: float4x4
    var frameIndex = UInt32(0)
    var rayCount = 0
    let maxDepth = 8
    
    var rayBuffer: MTLBuffer!
    var rayCountBuffer: MTLBuffer!
    var indirectDispatchBuffer: MTLBuffer!
    var intersectionBuffer: MTLBuffer!
    var outputImageSize: MTLSize!
    var outputImage: MTLTexture!
    
    var framesPerSecond: Float = 0
    var fpsSamples = 0
    
    let scene: Scene
    
    init?(metalKitView: MTKView, scene: Scene) {
        self.scene = scene
        self.projectionMatrix = scene.projectionMatrix
        self.device = metalKitView.device!
        
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize
        guard let buffer = self.device.makeBuffer(
            length: uniformBufferSize,
            options: .storageModeManaged
        ) else { return nil }
        
        self.dynamicUniformBuffer = buffer
        self.dynamicUniformBuffer.label = "UniformBuffer"
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to: Uniforms.self, capacity: 1)
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = .rgba16Float
        metalKitView.sampleCount = 1
        metalKitView.preferredFramesPerSecond = 120
        metalKitView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        
        let lastHandlerConstants = MTLFunctionConstantValues()
        let ptr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        ptr.pointee = true
        lastHandlerConstants.setConstantValue(ptr, type: .bool, index: 0)
        ptr.deallocate()
        
        rayGenerator = Renderer.buildComputePipelineWithDevice(device: device, name: "generateRays")!
        makeIndirectDispatch = Renderer.buildComputePipelineWithDevice(device: device, name: "makeIndirectDispatchArguments")!
        
        do {
            pipelineState = try Renderer.buildBlitPipelineWithDevice(
                device: device,
                metalKitView: metalKitView
            )
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        rayIntersector = MPSRayIntersector(device: device)
        //shadowRayIntersector = MPSRayIntersector(device: device)
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDescriptor) else { return nil }
        depthState = state
        
        super.init()
        
        self.setupRayIntersectors()
    }
    
    private func setupRayIntersectors() {
        rayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        rayIntersector.rayStride = MemoryLayout<Ray>.stride
        rayIntersector.intersectionDataType = .distancePrimitiveIndexInstanceIndexCoordinates
        rayIntersector.intersectionStride = MemoryLayout<Intersection>.stride
        
        //shadowRayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        //shadowRayIntersector.rayStride = MemoryLayout<ShadowRay>.stride
        //shadowRayIntersector.intersectionDataType = .distance
        //shadowRayIntersector.intersectionStride = MemoryLayout<Intersection>.stride
    }
    
    class func buildComputePipelineWithDevice(
        device: MTLDevice,
        name: String,
        constantValues: MTLFunctionConstantValues = MTLFunctionConstantValues(),
        linkedFunctions: MTLLinkedFunctions? = nil
    ) -> MTLComputePipelineState? {
        let library = device.makeDefaultLibrary()!
        
        do {
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = try library.makeFunction(name: name, constantValues: constantValues)
            descriptor.label = name
            descriptor.linkedFunctions = linkedFunctions
            return try library.device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        } catch {
            print("Unable to compile compute pipeline state. Error info: \(error)")
            return nil
        }
    }
    
    class func buildBlitPipelineWithDevice(
        device: MTLDevice,
        metalKitView: MTKView
    ) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "blitVertex")
        let fragmentFunction = library?.makeFunction(name: "blitFragment")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "BlitPipeline"
        //pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents())
            .bindMemory(to: Uniforms.self, capacity: 1)
    }
    
    private func updateState() {
        /// Update any state before rendering
        uniforms[0].frameIndex = frameIndex
        uniforms[0].projectionMatrix = projectionMatrix
        frameIndex += 1
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
                    print("frame took more than \(frameTime) seconds. Sleeping 3 seconds to not lock up system!")
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
            
            self.updateDynamicBufferState()
            self.updateState()
            
            if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
                computeEncoder.label = "Clear Ray Count"
                computeEncoder.fill(
                    buffer: rayCountBuffer, range: 0..<rayCountBuffer.length,
                    value: 0)
                computeEncoder.endEncoding()
            }
            
            //if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
            //    computeEncoder.label = "Clear Shadow Ray Count"
            //    computeEncoder.fill(buffer: shadowRayCountBuffer!, range: 0..<shadowRayCountBuffer!.length, value: 0)
            //    computeEncoder.endEncoding()
            //}
            
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
                computeEncoder.dispatchThreads(
                    outputImageSize,
                    threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
                computeEncoder.endEncoding()
            }
            
            var currentRayBufferOffset = 0
            var nextRayBufferOffset = rayBuffer.length / 2
            
            for depth in 0..<maxDepth {
                let rayCountBufferOffset = depth * MemoryLayout<UInt32>.stride
                //let isMaxDepth = (depth+1 == maxDepth)
                
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
                    //computeEncoder.setBuffer(
                    //    shadowRayBuffer, offset: 0,
                    //    index: ShadingBufferIndex.shadowRays.rawValue)
                    
                    // ray counters
                    computeEncoder.setBuffer(
                        rayCountBuffer,
                        offset: rayCountBufferOffset, index: ShadingBufferIndex.currentRayCount.rawValue)
                    computeEncoder.setBuffer(
                        rayCountBuffer,
                        offset: rayCountBufferOffset + MemoryLayout<UInt32>.stride, index: ShadingBufferIndex.nextRayCount.rawValue)
                    //computeEncoder.setBuffer(
                    //    shadowRayCountBuffer, offset: rayCountBufferOffset,
                    //    index: ShadingBufferIndex.shadowRayCount.rawValue)
                    
                    // geometry buffers
                    computeEncoder.setBuffer(
                        scene.mesh.vertices,
                        offset: 0, index: ShadingBufferIndex.vertices.rawValue)
                    computeEncoder.setBuffer(
                        scene.mesh.indices,
                        offset: 0, index: ShadingBufferIndex.vertexIndices.rawValue)
                    computeEncoder.setBuffer(
                        scene.mesh.normals,
                        offset: 0, index: ShadingBufferIndex.normals.rawValue)
                    computeEncoder.setBuffer(
                        scene.mesh.texCoords,
                        offset: 0, index: ShadingBufferIndex.texcoords.rawValue)
                    
                    // scene buffers
                    computeEncoder.setBuffer(
                        dynamicUniformBuffer,
                        offset: 0, index: ShadingBufferIndex.uniforms.rawValue)
                    computeEncoder.setBuffer(
                        scene.instanceBuffer,
                        offset: 0, index: ShadingBufferIndex.perInstanceData.rawValue)
                    computeEncoder.setBuffer(
                        scene.mesh.materials,
                        offset: 0, index: ShadingBufferIndex.materials.rawValue)
                    
                    // shader table
                    computeEncoder.setVisibleFunctionTable(
                        scene.shaderFunctionTable,
                        bufferIndex: ShadingBufferIndex.functionTable.rawValue)
                    
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
                
                // ping pong
                (currentRayBufferOffset, nextRayBufferOffset) = (nextRayBufferOffset, currentRayBufferOffset)
            }
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                /// Final pass rendering code here
                renderEncoder.label = "Blit Render"
                
                renderEncoder.setCullMode(.back)
                renderEncoder.setFrontFacing(.counterClockwise)
                renderEncoder.setRenderPipelineState(pipelineState)
                renderEncoder.setDepthStencilState(depthState)
                
                renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset: 0, index: 0)
                renderEncoder.setFragmentTexture(outputImage, index: 0)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                
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
        //let shadowCounts = shadowRayCountBuffer!.contents().bindMemory(to: UInt32.self, capacity: maxDepth)
        var totalRayCount = 0
        
        for depth in 0..<maxDepth {
            totalRayCount += Int(counts[depth])// + shadowCounts[depth])
            print(depth, counts[depth])//, shadowCounts[depth])
        }
        print("total", totalRayCount)
        print()
        
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
    }
    
    func reset() {
        frameIndex = 0
        makeOutputImage()
    }
    
    func updateProjection(by multiplying: float4x4) {
        projectionMatrix = projectionMatrix * multiplying.transpose
        reset()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        outputImageSize = MTLSizeMake(Int(size.width), Int(size.height), 1)
        
        makeOutputImage()
        
        rayCount = outputImageSize.width * outputImageSize.height
        rayBuffer = device.makeBuffer(
            length: 2 * rayCount * MemoryLayout<Ray>.stride,
            options: .storageModePrivate)!
        //shadowRayBuffer = device.makeBuffer(
        //    length: rayCount * MemoryLayout<ShadowRay>.stride,
        //    options: .storageModePrivate)
        rayCountBuffer = device.makeBuffer(
            length: (maxDepth+1) * MemoryLayout<UInt32>.stride,
            options: .storageModeShared)!
        //shadowRayCountBuffer = device.makeBuffer(
        //    length: maxDepth * MemoryLayout<UInt32>.stride,
        //    options: .storageModeShared)
        intersectionBuffer = device.makeBuffer(
            length: rayCount * MemoryLayout<Intersection>.stride,
            options: .storageModePrivate)!
        indirectDispatchBuffer = device.makeBuffer(
            length: MemoryLayout<MTLDispatchThreadgroupsIndirectArguments>.stride,
            options: .storageModePrivate)!
        
        rayBuffer.label = "Rays"
        //shadowRayBuffer!.label = "Shadow rays"
        intersectionBuffer.label = "Intersections"
        
        frameIndex = 0
    }
    
    func saveFrame() {
        let norm = Float(1) / Float(frameIndex)
        let img = outputImage!
        let numComponents = 4
        let bytesPerRow = 4 * img.width * MemoryLayout<Float>.stride // @todo hack
        let data = UnsafeMutableRawPointer.allocate(
            byteCount: bytesPerRow * img.height,
            alignment: 16
        )
        defer {
            data.deallocate()
        }
        
        // load image data
        img.getBytes(
            data,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: img.width, height: img.height, depth: 1)),
            mipmapLevel: 0
        )
        
        // normalize image data
        let buffer = data.bindMemory(to: Float.self, capacity: numComponents * img.width * img.height)
        for i in 0..<(img.width * img.height) {
            buffer[numComponents*i + 0] *= norm
            buffer[numComponents*i + 1] *= norm
            buffer[numComponents*i + 2] *= norm
            buffer[numComponents*i + 3] = 1
        }
        
        for y in 0..<(img.height / 2) {
            let y2 = img.height - (y + 1)
            let elementsPerRow = numComponents * img.width
            for i in 0..<elementsPerRow {
                let tmp = buffer[y * elementsPerRow + i]
                buffer[y * elementsPerRow + i] = buffer[y2 * elementsPerRow + i]
                buffer[y2 * elementsPerRow + i] = tmp
            }
        }
        
        // write data out
        let err = UnsafeMutablePointer<Optional<UnsafePointer<CChar>>>.allocate(capacity: 1)
        err.pointee = UnsafePointer(bitPattern: 0)
        defer {
            err.deallocate()
        }
        
        let resourcesURL = URL(fileURLWithPath: "/Users/alex/Desktop", isDirectory: true)
        let fileName = resourcesURL.appendingPathComponent("frame.exr")
        
        SaveEXR(
            data.bindMemory(to: Float.self, capacity: numComponents * img.width * img.height),
            Int32(img.width), Int32(img.height),
            Int32(numComponents),
            0,
            NSString(string: fileName.path).utf8String!,
            err
        )
        
        if let p = err.pointee {
            print(NSString(utf8String: p)!)
        } else {
            print("Saved to EXR file")
        }
    }
}
