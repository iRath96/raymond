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
    let imageFillPipelineState: MTLComputePipelineState
    let intersectionHandler: MTLComputePipelineState
    let lastIntersectionHandler: MTLComputePipelineState
    let rayGenerator: MTLComputePipelineState
    let makeIndirectDispatch: MTLComputePipelineState
    
    let accelerationStructure: MPSInstanceAccelerationStructure
    let rayIntersector: MPSRayIntersector
    let shadowRayIntersector: MPSRayIntersector
    
    let inFlightSemaphore = DispatchSemaphore(value: 1)
    var uniforms: UnsafeMutablePointer<Uniforms>
    
    var projectionMatrix: float4x4
    var frameIndex = UInt32(0)
    var rayCount = 0
    let maxDepth = 2
    
    var rayBuffer: MTLBuffer?
    var rayCountBuffer: MTLBuffer?
    var indirectDispatchBuffer: MTLBuffer?
    var shadowRayCountBuffer: MTLBuffer?
    var shadowRayBuffer: MTLBuffer?
    var intersectionBuffer: MTLBuffer?
    var instanceBuffer: MTLBuffer?
    var outputImageSize: MTLSize?
    var outputImage: MTLTexture?
    var shaderFunctionTable: MTLVisibleFunctionTable?
    var shaderFunctionTableLast: MTLVisibleFunctionTable?
    var contextBuffer: MTLBuffer?
    var resourcesRead: [MTLResource]
    
    var mesh: Mesh
    
    var framesPerSecond: Float = 0
    var fpsSamples = 0
    
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize
        
        guard let buffer = self.device.makeBuffer(length: uniformBufferSize, options: .storageModeManaged) else { return nil }
        dynamicUniformBuffer = buffer
        
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
        
        imageFillPipelineState = Renderer.buildComputePipelineWithDevice(device: device, name: "background")!
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
        
        do {
            let path = URL(filePath: "/Users/alex/Desktop/evermotion/unzipped/AI55_008/AI55_008.json")
            let scene = try SceneLoader().makeScene(fromURL: path)
            
            var instanceLoader = InstanceLoader()
            /*let entityNames = [
                "AI55_008_floor_001",
                "Am185_12_obj_169",
                "AI55_008_sit_pillows_021",
                "Am185_12_obj_131",
                "Am185_12_obj_127",
                "Am185_12_obj_126",
                "Am185_12_obj_129",
                "Am185_12_obj_128",
                "AI55_008_Golden_Pot_001",
                "AM208_018_Saucer002",
                "AM208_018_Candle_002",
                "AI55_008_sit_pillows_013",
                "Am185_12_obj_121",
                "AI55_008_sit_pillows_009",
                "AI55_008_Chair_Brown002",
                "AI55_008_Light009",
                "AI55_008_Plane_002",
                "AI55_008_sit_pillows_012",
                "Am185_12_obj_130",
                "AI55_008_Pill_460",
                "AI55_008_Pill_459",
                "AI55_008_Pill_458",
                "AI55_008_Pill_453",
                "AI55_008_Pill_452",
                "AI55_008_Pill_439",
                "AI55_008_Pill_447",
                "AI55_008_sit_001",
                "AI55_008_Stair",
                "AI55_008_Wall_001",
                "AI55_008_Wall_Pattern_002",
                "AI55_008_Wall_Pattern_001",
                "AI55_008_sit_002",
                "AI55_008_Metal_Frame_009",
                "AM208_018_Vessel003",
                "Am185_12_obj_123",
                "AM141_035_obj_148",
                "AM141_035_obj_145",
                "AM141_035_obj_146",
                "AM141_035_obj_152",
                "AM201_032_Dypsis_Lanceloata_leafs002"
            ]*/
            let entityNames = [String](scene.entities.keys.sorted())//[0..<800]
            for entityName in entityNames {
                NSLog("adding entity \(entityName)")
                try instanceLoader.addEntity(scene.entities[entityName]!)
            }
            
            let instancing = try instanceLoader.build(withDevice: device)
            
            var meshLoader = MeshLoader()
            for shapeName in instancing.shapeNames {
                NSLog("adding shape \(shapeName)")
                try meshLoader.addShape(scene.shapes[shapeName]!)
            }
            
            NSLog("building acceleration structures")
            mesh = try meshLoader.build(withDevice: device)
            
            let codegenOptions: Codegen.Options = [ .useFunctionTable ]
            var codegen = Codegen(basePath: path, device: device, options: codegenOptions)
            for materialName in mesh.materialNames {
                NSLog("generating shader for \(materialName)")
                try codegen.addMaterial(scene.materials[materialName]!)
            }
            
            NSLog("generating shaders")
            let library = try codegen.build()
            
            let linkedFunctions = MTLLinkedFunctions()
            linkedFunctions.functions = []
            if codegenOptions.contains(.useFunctionTable) {
                for index in 0..<mesh.materialNames.count {
                    NSLog("making function material_\(index)")
                    let function = library.makeFunction(name: "material_\(index)")!
                    linkedFunctions.functions!.append(function)
                }
            }
            
            NSLog("making function handleIntersections")
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = library.makeFunction(
                name: "handleIntersections")
            descriptor.label = "handleIntersections"
            descriptor.linkedFunctions = linkedFunctions
            intersectionHandler = try library.device.makeComputePipelineState(
                descriptor: descriptor,
                options: [],
                reflection: nil)
            
            /*NSLog("saving to binary")
            let binDescriptor = MTLBinaryArchiveDescriptor()
            let binArchive = try device.makeBinaryArchive(descriptor: binDescriptor)
            try binArchive.addComputePipelineFunctions(descriptor: descriptor)
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            try binArchive.serialize(to: desktopURL.appending(path: "binary.metallib"))*/
            
            NSLog("making function handleIntersections (last)")
            descriptor.computeFunction = try library.makeFunction(
                name: "handleIntersections",
                constantValues: lastHandlerConstants)
            lastIntersectionHandler = try library.device.makeComputePipelineState(
                descriptor: descriptor,
                options: [],
                reflection: nil)
            
            let fnTableDescriptor = MTLVisibleFunctionTableDescriptor()
            fnTableDescriptor.functionCount = mesh.materialNames.count
            
            shaderFunctionTable = intersectionHandler.makeVisibleFunctionTable(
                descriptor: fnTableDescriptor)
            shaderFunctionTableLast = lastIntersectionHandler.makeVisibleFunctionTable(
                descriptor: fnTableDescriptor)
            
            if codegenOptions.contains(.useFunctionTable) {
                for index in 0..<mesh.materialNames.count {
                    let function = linkedFunctions.functions![index]
                    shaderFunctionTable!.setFunction(
                        intersectionHandler.functionHandle(function: function)!,
                        index: index)
                    shaderFunctionTableLast!.setFunction(
                        lastIntersectionHandler.functionHandle(function: function)!,
                        index: index)
                }
            }
            
            instanceBuffer = device.makeBuffer(
                length: MemoryLayout<PerInstanceData>.stride * Int(instancing.instanceCount))
            instanceBuffer!.label = "Per instance data"
            let instances = instanceBuffer!.contents().assumingMemoryBound(to: PerInstanceData.self)
            for index in 0..<Int(instancing.instanceCount) {
                let instanceData = instances.advanced(by: index)
                let shapeInfo = mesh.shapeInfos[Int(instancing.indicesArray[index])]
                instanceData.pointee = PerInstanceData(
                    vertexOffset: shapeInfo.vertexOffset,
                    faceOffset: shapeInfo.faceOffset,
                    pointTransform: instancing.pointTransforms[index],
                    normalTransform: instancing.normalTransforms[index]
                )
            }
            
            let argumentEncoder = descriptor.computeFunction!.makeArgumentEncoder(bufferIndex: ShadingBufferIndex.context.rawValue)
            contextBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: .storageModeShared)!
            argumentEncoder.setArgumentBuffer(contextBuffer, offset: 0)

            resourcesRead = []
            for (index, texture) in codegen.textures.enumerated() {
                argumentEncoder.setTexture(texture, index: index)
                resourcesRead.append(texture)
            }

            NSLog("building top level AS")
            accelerationStructure = MPSInstanceAccelerationStructure(group: mesh.accelerationGroup)
            accelerationStructure.accelerationStructures = mesh.accelerationStructures
            accelerationStructure.instanceCount = Int(instancing.instanceCount)
            accelerationStructure.instanceBuffer = instancing.indices
            accelerationStructure.transformType = .float4x4
            accelerationStructure.transformBuffer = instancing.transforms
            accelerationStructure.rebuild()
            
            NSLog("done!")
            
            projectionMatrix = float4x4([
                SIMD4([ 0, 0, 1, 314.8 ]),
                SIMD4([ 1, 0, 0, -248.2 ]),
                SIMD4([ 0, 1, 0, 160.5 ]),
                SIMD4([ 0, 0, 0, 1 ]),
            ])
        } catch {
            print("Unable to compile scene.  Error info: \(error)")
            return nil
        }
        
        rayIntersector = MPSRayIntersector(device: device)
        shadowRayIntersector = MPSRayIntersector(device: device)
        
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
        
        shadowRayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        shadowRayIntersector.rayStride = MemoryLayout<ShadowRay>.stride
        shadowRayIntersector.intersectionDataType = .distance
        shadowRayIntersector.intersectionStride = MemoryLayout<Intersection>.stride
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
                    let width = self.outputImageSize!.width
                    let height = self.outputImageSize!.height
                    
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
                computeEncoder.fill(buffer: rayCountBuffer!, range: 0..<rayCountBuffer!.length, value: 0)
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
                computeEncoder.setBuffer(rayBuffer, offset: 0, index: GeneratorBufferIndex.rays.rawValue)
                computeEncoder.setBuffer(rayCountBuffer, offset: 0, index: GeneratorBufferIndex.rayCount.rawValue)
                computeEncoder.setBuffer(
                    dynamicUniformBuffer,
                    offset: 0,
                    index: GeneratorBufferIndex.uniforms.rawValue)
                computeEncoder.dispatchThreads(outputImageSize!, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
                computeEncoder.endEncoding()
            }
            
            var currentRayBufferOffset = 0
            var nextRayBufferOffset = rayBuffer!.length / 2
            
            for depth in 0..<maxDepth {
                let rayCountBufferOffset = depth * MemoryLayout<UInt32>.stride
                let isMaxDepth = (depth+1 == maxDepth)
                
                rayIntersector.encodeIntersection(
                    commandBuffer: commandBuffer,
                    intersectionType: .nearest,
                    rayBuffer: rayBuffer!,
                    rayBufferOffset: currentRayBufferOffset,
                    intersectionBuffer: intersectionBuffer!,
                    intersectionBufferOffset: 0,
                    rayCountBuffer: rayCountBuffer!,
                    rayCountBufferOffset: rayCountBufferOffset,
                    accelerationStructure: accelerationStructure)
                
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
                    computeEncoder.setComputePipelineState(isMaxDepth ?
                        lastIntersectionHandler : intersectionHandler)
                    
                    // ray buffers
                    computeEncoder.setBuffer(intersectionBuffer, offset: 0, index: ShadingBufferIndex.intersections.rawValue)
                    computeEncoder.setBuffer(rayBuffer, offset: currentRayBufferOffset, index: ShadingBufferIndex.rays.rawValue)
                    computeEncoder.setBuffer(rayBuffer, offset: nextRayBufferOffset, index: ShadingBufferIndex.nextRays.rawValue)
                    computeEncoder.setBuffer(shadowRayBuffer, offset: 0, index: ShadingBufferIndex.shadowRays.rawValue)
                    
                    // ray counters
                    computeEncoder.setBuffer(rayCountBuffer!, offset: rayCountBufferOffset, index: ShadingBufferIndex.currentRayCount.rawValue)
                    computeEncoder.setBuffer(rayCountBuffer!, offset: rayCountBufferOffset + MemoryLayout<UInt32>.stride, index: ShadingBufferIndex.nextRayCount.rawValue)
                    computeEncoder.setBuffer(shadowRayCountBuffer!, offset: rayCountBufferOffset, index: ShadingBufferIndex.shadowRayCount.rawValue)
                    
                    // geometry buffers
                    computeEncoder.setBuffer(mesh.vertices, offset: 0, index: ShadingBufferIndex.vertices.rawValue)
                    computeEncoder.setBuffer(mesh.indices, offset: 0, index: ShadingBufferIndex.vertexIndices.rawValue)
                    computeEncoder.setBuffer(mesh.normals, offset: 0, index: ShadingBufferIndex.normals.rawValue)
                    computeEncoder.setBuffer(mesh.texCoords, offset: 0, index: ShadingBufferIndex.texcoords.rawValue)
                    
                    // scene buffers
                    computeEncoder.setBuffer(dynamicUniformBuffer, offset: 0, index: ShadingBufferIndex.uniforms.rawValue)
                    computeEncoder.setBuffer(instanceBuffer, offset: 0, index: ShadingBufferIndex.perInstanceData.rawValue)
                    computeEncoder.setBuffer(mesh.materials, offset: 0, index: ShadingBufferIndex.materials.rawValue)
                    
                    // shader table
                    computeEncoder.setVisibleFunctionTable(isMaxDepth ?
                        shaderFunctionTableLast : shaderFunctionTable,
                        bufferIndex: ShadingBufferIndex.functionTable.rawValue)
                    
                    computeEncoder.setBuffer(contextBuffer, offset: 0, index: ShadingBufferIndex.context.rawValue)
                    computeEncoder.useResources(resourcesRead, usage: .read)
                    
                    computeEncoder.dispatchThreadgroups(
                        indirectBuffer: indirectDispatchBuffer!,
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
        let counts = rayCountBuffer!.contents().bindMemory(to: UInt32.self, capacity: maxDepth)
        let shadowCounts = shadowRayCountBuffer!.contents().bindMemory(to: UInt32.self, capacity: maxDepth)
        var totalRayCount = 0
        
        for depth in 0..<maxDepth {
            totalRayCount += Int(counts[depth] + shadowCounts[depth])
            print(depth, counts[depth], shadowCounts[depth])
        }
        print("total", totalRayCount)
        print()
        
        return totalRayCount
    }
    
    private func makeOutputImage() {
        let outputImageDescriptor = MTLTextureDescriptor()
        outputImageDescriptor.pixelFormat = .rgba32Float
        outputImageDescriptor.width = outputImageSize!.width
        outputImageDescriptor.height = outputImageSize!.height
        outputImageDescriptor.usage = [ .shaderRead, .shaderWrite ]
        outputImageDescriptor.storageMode = .shared
        outputImage = device.makeTexture(descriptor: outputImageDescriptor)!
        outputImage!.label = "Output image"
    }
    
    func reset() {
        frameIndex = 0
        makeOutputImage()
    }
    
    func updateProjection(by multiplying: float4x4) {
        projectionMatrix = multiplying * projectionMatrix
        reset()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        outputImageSize = MTLSizeMake(Int(size.width), Int(size.height), 1)
        
        makeOutputImage()
        
        rayCount = outputImageSize!.width * outputImageSize!.height
        rayBuffer = device.makeBuffer(
            length: 2 * rayCount * MemoryLayout<Ray>.stride,
            options: .storageModePrivate)
        shadowRayBuffer = device.makeBuffer(
            length: rayCount * MemoryLayout<ShadowRay>.stride,
            options: .storageModePrivate)
        rayCountBuffer = device.makeBuffer(
            length: (maxDepth+1) * MemoryLayout<UInt32>.stride,
            options: .storageModeShared)
        shadowRayCountBuffer = device.makeBuffer(
            length: maxDepth * MemoryLayout<UInt32>.stride,
            options: .storageModeShared)
        intersectionBuffer = device.makeBuffer(
            length: rayCount * MemoryLayout<Intersection>.stride,
            options: .storageModePrivate)
        indirectDispatchBuffer = device.makeBuffer(
            length: MemoryLayout<MTLDispatchThreadgroupsIndirectArguments>.stride,
            options: .storageModePrivate)
        
        rayBuffer!.label = "Rays"
        shadowRayBuffer!.label = "Shadow rays"
        intersectionBuffer!.label = "Intersections"
        
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
