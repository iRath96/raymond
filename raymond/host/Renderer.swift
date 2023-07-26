import Metal
import MetalKit
import MetalPerformanceShaders
import simd
import MetalUtils

fileprivate let log = SwiftLogger(named: "renderer")

enum RendererError: Error {
    case badVertexDescriptor
}

class RendererCounters {
    enum Error: Swift.Error {
        case counterSetNotFound
        case counterNotSupported
    }
    
    enum Stage {
        case rayGeneration
        case handleIntersections(Int)
        case handleShadowRays(Int)
        case tonemapping
    }
    
    struct Report {
        var totalTime: Double = 0
        var reportedTime: Double = 0
        var sections: [Section] = []
        
        struct Entry {
            var name: String
            var time: Double
            var rays: UInt32
        }
        
        struct Section {
            var name: String
            var entries: [Entry] = []
            var totalTime: Double = 0
            var reportedTime: Double = 0
        }
        
        static func +(left: Report, right: Report) -> Report {
            var newReport = Report()
            newReport.totalTime = left.totalTime + right.totalTime
            newReport.reportedTime = left.reportedTime + right.reportedTime
            newReport.sections = left.sections
            
            for section in right.sections {
                if var existing = newReport.sections.first(where: { $0.name == section.name }) {
                    existing.reportedTime += section.reportedTime
                    existing.totalTime += section.totalTime
                    
                    for entry in section.entries {
                        if var e = existing.entries.first(where: { $0.name == entry.name }) {
                            e.time += entry.time
                            e.rays += entry.rays
                        } else {
                            existing.entries.append(entry)
                        }
                    }
                } else {
                    newReport.sections.append(section)
                }
            }
            
            return newReport
        }
        
        static func /(left: Report, right: Int) -> Report {
            let norm = Double(1) / Double(right)
            
            var newReport = left
            newReport.totalTime *= norm
            newReport.reportedTime *= norm
            
            for var section in newReport.sections {
                section.totalTime *= norm
                section.reportedTime *= norm
                
                for var entry in section.entries {
                    entry.rays /= UInt32(right)
                    entry.time *= norm
                }
            }
            
            return newReport
        }
    }
    
    private class ReportAccumulator {
        var sampleCount = 0
        var accumulator = Report()
        
        var average: Report {
            get {
                return accumulator / sampleCount
            }
        }
        
        func reset() {
            sampleCount = 0
        }
        
        func add(report: Report) {
            sampleCount += 1
            if sampleCount == 1 {
                accumulator = report
                return
            }
            
            accumulator = accumulator + report
        }
    }
    
    private var device: MTLDevice
    private var counterBuffer: MTLCounterSampleBuffer
    private var maxDepth: Int
    
    private var reportCounter = 0
    private var reportAccumulator = ReportAccumulator()
    
    private static func sampleCount(maxDepth: Int) -> Int {
        let radianceCacheSteps = 3
        return 2 * (
            1 +              // ray generation
            maxDepth +       // intersections
            (maxDepth - 1) + // shadow rays
            1                // tonemapping
        )
    }
    
    private func sampleIndex(for stage: Stage) -> Int {
        switch stage {
            case .rayGeneration:
                return 0
            case .handleIntersections(let depth):
                return 2 + 0 + 4 * depth
            case .handleShadowRays(let depth):
                return 2 + 2 + 4 * depth
            case .tonemapping:
                return 2 + (4 * maxDepth - 2)
        }
    }
    
    init(on device: MTLDevice, withMaxDepth depth: Int) throws {
        self.device = device
        self.maxDepth = depth
        
        guard let counterset = self.device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) else {
            throw Error.counterSetNotFound
        }
        guard counterset.counters.contains(where: { $0.name == MTLCommonCounter.timestamp.rawValue }) else {
            throw Error.counterNotSupported
        }
        
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = counterset
        descriptor.storageMode = .shared
        descriptor.sampleCount = RendererCounters.sampleCount(maxDepth: maxDepth)
        
        counterBuffer = try device.makeCounterSampleBuffer(descriptor: descriptor)
    }
    
    func makeComputeCommandEncoder(in commandBuffer: MTLCommandBuffer, for stage: Stage) -> MTLComputeCommandEncoder? {
        let desc = MTLComputePassDescriptor()
        let attach = desc.sampleBufferAttachments[0]!
        attach.sampleBuffer = counterBuffer
        attach.startOfEncoderSampleIndex = sampleIndex(for: stage)
        attach.endOfEncoderSampleIndex = attach.startOfEncoderSampleIndex + 1
        return commandBuffer.makeComputeCommandEncoder(descriptor: desc)
    }
    
    func report(rayCounts: [UInt32], shadowRayCounts: [UInt32]) -> Report {
        let sampleCount = self.counterBuffer.sampleCount
        let counterData = try! self.counterBuffer.resolveCounterRange(0..<sampleCount)
        let timestampSamples = Array<MTLCounterResultTimestamp>(unsafeUninitializedCapacity: sampleCount) { buffer, initializedCount in
            let elementSize = MemoryLayout<MTLCounterResultTimestamp>.size
            let bytesCopied = counterData!.copyBytes(to: buffer)
            initializedCount = bytesCopied / elementSize
        }
        
        var result = Report()
        var currentSection: Report.Section!
        
        func report(stage: Stage, as name: String, trace: Bool = false) {
            let index = sampleIndex(for: stage) + (trace ? -1 : 0)
            let time = (Double(timestampSamples[index + 1].timestamp) - Double(timestampSamples[index].timestamp)) / Double(NSEC_PER_SEC)
            
            var rays: UInt32
            switch stage {
                case .rayGeneration: rays = rayCounts[0]
                case .handleIntersections(let depth): rays = rayCounts[depth]
                case .handleShadowRays(let depth): rays = shadowRayCounts[depth]
                default: rays = 0
            }
            
            result.reportedTime += time
            currentSection.reportedTime += time
            currentSection.entries.append(.init(name: name, time: time, rays: rays))
        }
        
        func section(named name: String, body: () -> Void) {
            currentSection = Report.Section(name: name)
            body()
            result.sections.append(currentSection)
        }
        
        section(named: "Preproc") {
            report(stage: .rayGeneration, as: "raygen")
        }
        
        for depth in 0..<maxDepth {
            section(named: "Depth \(depth)") {
                report(stage: .handleIntersections(depth), as: "ctrace", trace: true)
                report(stage: .handleIntersections(depth), as: "chit")
                if depth + 1 < maxDepth {
                    report(stage: .handleShadowRays(depth), as: "atrace", trace: true)
                    report(stage: .handleShadowRays(depth), as: "ahit")
                }
            }
        }
        
        section(named: "Postproc") {
            report(stage: .tonemapping, as: "tonemap")
        }
        
        result.totalTime = (Double(timestampSamples.last!.timestamp) - Double(timestampSamples.first!.timestamp)) / Double(NSEC_PER_SEC)
        return result
    }
    
    private func dump(report r: Report) {
        reportCounter += 1
        print("Report #\(reportCounter)")
        
        print(String(format: "Statistics\t%6.0lf us\t%6.0lf us\t%6.1f FPS",
            r.reportedTime * 1e+6,
            r.totalTime * 1e+6,
            1 / r.totalTime
        ))
        for section in r.sections {
            print()
            print(String(format: "* %@\t%6.0lf us\t(%5.1f %%)",
                section.name,
                section.reportedTime * 1e+6,
                100 * section.reportedTime / r.reportedTime
            ))
            for entry in section.entries {
                print(String(format: "  * %@\t%6.0lf us\t%7.1lf kray\t%7.1lf Mray/s",
                    entry.name,
                    entry.time * 1e+6,
                    Double(entry.rays) / 1e+3,
                    (Double(entry.rays) / entry.time) / 1e+6))
            }
        }
        print()
    }
    
    func dump(rayCounts: [UInt32], shadowRayCounts: [UInt32]) {
        let r = report(rayCounts: rayCounts, shadowRayCounts: shadowRayCounts)
        reportAccumulator.add(report: r)
        
        if reportAccumulator.sampleCount >= 100 {
            dump(report: reportAccumulator.average)
            reportAccumulator.reset()
        }
    }
}

@objc class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let counters: RendererCounters
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var depthState: MTLDepthStencilState
    
    let blitPipeline: MTLRenderPipelineState
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
    
    var printfBuffer: PrintfBuffer
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
    
    convenience init?(metalKitView: MTKView, printfBuffer: PrintfBuffer, scene: Scene) {
        self.init(device: metalKitView.device!, printfBuffer: printfBuffer, scene: scene)
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = .rgba16Float
        metalKitView.sampleCount = 1
        metalKitView.preferredFramesPerSecond = 120
        metalKitView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    }
    
    required init?(device: MTLDevice, printfBuffer: PrintfBuffer, scene: Scene) {
        self.scene = scene
        self.device = device
        self.printfBuffer = printfBuffer
        
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        (self.dynamicUniformBuffer, uniforms) = self.device.makeBufferAndPointer(
            type: DeviceUniforms.self,
            count: 1,
            name: "Uniforms")
        uniforms[0] = DeviceUniforms(
            numLensSurfaces: 0,
            frameIndex: 0,
            randomSeed: 0,
            accumulate: true,
            lensSpectral: true,
            sensorScale: 1,
            cameraScale: 0.001,
            focus: 0,
            exposure: 1,
            stopIndex: 0,
            relativeStop: 1,
            numApertureBlades: 7,
            samplingMode: .mis,
            tonemapping: .linear,
            rr: .throughput,
            rrDepth: 0,
            outputChannel: .image
        )
        
        let lastHandlerConstants = MTLFunctionConstantValues()
        let ptr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        ptr.pointee = true
        lastHandlerConstants.setConstantValue(ptr, type: .bool, index: 0)
        ptr.deallocate()

        func buildPipeline(_ name: String) -> MTLComputePipelineState {
            return Renderer.buildComputePipelineWithDevice(
                library: scene.library,
                name: name,
                constantValues: printfBuffer.constants)!
        }
        
        rayGenerator         = buildPipeline("generateRays")
        imageNormalizer      = buildPipeline("normalizeImage")
        makeIndirectDispatch = buildPipeline("makeIndirectDispatchArguments")
        
        blitPipeline = Renderer.buildBlitPipelineWithDevice(library: scene.library)!
        rayIntersector = .init(device: device)
        shadowRayIntersector = .init(device: device)

        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDescriptor) else { return nil }
        depthState = state
        
        outputImageSize = MTLSizeMake(0, 0, 1)
        lensBuffer = device.makeBuffer(length: 100) /// @todo hack
        lensBuffer.label = "Lens Buffer Placeholder"

        self.counters = try! .init(on: device, withMaxDepth: maxDepth)
        
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
    
    class func buildBlitPipelineWithDevice(library: MTLLibrary) -> MTLRenderPipelineState? {
        do {
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
        } catch {
            log.error("Unable to compile compute pipeline state. Error info: \(error)")
            return nil
        }
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents())
            .bindMemory(to: DeviceUniforms.self, capacity: 1)
    }
    
    private func updateState() {
        /// Update any state before rendering
        uniforms[0].frameIndex = frameIndex
        uniforms[0].randomSeed += 1
        frameIndex += 1
    }
    
    @objc func execute(in commandBuffer: MTLCommandBuffer) {
        let semaphore = inFlightSemaphore
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        
        self.updateDynamicBufferState()
        self.updateState()

        // MARK: preprocessing
        
        if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
            computeEncoder.label = "Clear Ray Count"
            computeEncoder.fill(
                buffer: rayCountBuffer, range: 0..<rayCountBuffer.length,
                value: 0)
            computeEncoder.endEncoding()
        }
        
        if let computeEncoder = commandBuffer.makeBlitCommandEncoder() {
            computeEncoder.label = "Clear Shadow Ray Count"
            computeEncoder.fill(
                buffer: shadowRayCountBuffer, range: 0..<shadowRayCountBuffer.length,
                value: 0)
            computeEncoder.endEncoding()
        }

        func makeTimedComputeCommandEncoder(for stage: RendererCounters.Stage) -> MTLComputeCommandEncoder? {
            return counters.makeComputeCommandEncoder(in: commandBuffer, for: stage)
        }
        
        if let computeEncoder = makeTimedComputeCommandEncoder(for: .rayGeneration) {
            computeEncoder.label = "Primary Ray Generation"
            computeEncoder.setComputePipelineState(rayGenerator)
            computeEncoder.setTexture(outputImage, index: 0)
            computeEncoder.setBuffer(
                rayBuffer, offset: 0,
                index: GeneratorBufferIndex.rays.rawValue)
            computeEncoder.setBuffer(
                rayCountBuffer, offset: 0,
                index: GeneratorBufferIndex.rayCount.rawValue)
            computeEncoder.setBuffer(
                dynamicUniformBuffer, offset: 0,
                index: GeneratorBufferIndex.uniforms.rawValue)
            computeEncoder.setBuffer(
                scene.contextBuffer, offset: 0,
                index: GeneratorBufferIndex.context.rawValue)
            computeEncoder.setBuffer(
                lensBuffer, offset: 0,
                index: GeneratorBufferIndex.lens.rawValue)
            computeEncoder.useResource(printfBuffer.buffer, usage: [ .read, .write ])
            computeEncoder.dispatchThreads(
                outputImageSize,
                threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            computeEncoder.endEncoding()
        }
        
        var currentRayBufferOffset = 0
        var nextRayBufferOffset = rayBuffer.length / 2
        
        for depth in 0..<maxDepth {
            let rayCountBufferOffset = depth * MemoryLayout<UInt32>.stride
            let isMaxDepth = (depth + 1 == maxDepth)
            
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
            
            if let computeEncoder = makeTimedComputeCommandEncoder(for: .handleIntersections(depth)) {
                computeEncoder.label = "Shade Rays and Secondary Ray Generation"
                computeEncoder.setTexture(outputImage, index: 0)
                computeEncoder.setComputePipelineState(scene.intersectionHandler)
                
                /// ray buffers
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
                
                /// ray counters
                computeEncoder.setBuffer(
                    rayCountBuffer, offset: rayCountBufferOffset,
                    index: ShadingBufferIndex.currentRayCount.rawValue)
                computeEncoder.setBuffer(
                    rayCountBuffer, offset: rayCountBufferOffset + MemoryLayout<UInt32>.stride,
                    index: ShadingBufferIndex.nextRayCount.rawValue)
                computeEncoder.setBuffer(
                    shadowRayCountBuffer, offset: rayCountBufferOffset,
                    index: ShadingBufferIndex.shadowRayCount.rawValue)
                
                /// scene buffers
                computeEncoder.setBuffer(
                    dynamicUniformBuffer, offset: 0,
                    index: ShadingBufferIndex.uniforms.rawValue)
                
                /// shader table
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
                rayBuffer: shadowRayBuffer,
                rayBufferOffset: 0,
                intersectionBuffer: intersectionBuffer,
                intersectionBufferOffset: 0,
                rayCountBuffer: shadowRayCountBuffer,
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
            
            if let computeEncoder = makeTimedComputeCommandEncoder(for: .handleShadowRays(depth)) {
                computeEncoder.label = "Shade Shadow Rays"
                computeEncoder.setTexture(outputImage, index: 0)
                computeEncoder.setComputePipelineState(scene.shadowRayHandler)
                computeEncoder.setBuffer(
                    intersectionBuffer, offset: 0,
                    index: ShadowBufferIndex.intersections.rawValue)
                computeEncoder.setBuffer(
                    shadowRayBuffer, offset: 0,
                    index: ShadowBufferIndex.shadowRays.rawValue)
                computeEncoder.setBuffer(
                    shadowRayCountBuffer, offset: rayCountBufferOffset,
                    index: ShadowBufferIndex.rayCount.rawValue)
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

        // MARK: postprocessing
        
        if let computeEncoder = makeTimedComputeCommandEncoder(for: .tonemapping) {
            computeEncoder.label = "Normalize output image"
            computeEncoder.setTexture(outputImage, index: 0)
            computeEncoder.setTexture(normalizedImage, index: 1)
            computeEncoder.setBuffer(dynamicUniformBuffer, offset: 0, index: 0)
            computeEncoder.setComputePipelineState(imageNormalizer)
            computeEncoder.dispatchThreads(outputImageSize, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            computeEncoder.endEncoding()
        }
        
        commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
            self.printfBuffer.execute()

            let rayCounts = self.rayCountBuffer.toArray(type: UInt32.self)
            let shadowRayCounts = self.shadowRayCountBuffer.toArray(type: UInt32.self)
            self.counters.dump(rayCounts: rayCounts, shadowRayCounts: shadowRayCounts)

            semaphore.signal()
        }
    }
    
    @objc func draw(encoder renderEncoder: MTLRenderCommandEncoder) {
        /// Final pass rendering code here
        renderEncoder.label = "Blit Render"
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(blitPipeline)
        renderEncoder.setDepthStencilState(depthState)
        
        renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(outputImage, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    
    func draw(in view: MTKView) {}
    
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
        self.lensBuffer.label = "Lens Buffer"
        uniforms[0].numLensSurfaces = lens.numSurfaces
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
            options: .storageModePrivate,
            name: "Rays")
        shadowRayBuffer = device.makeBuffer(
            type: DeviceShadowRay.self,
            count: rayCount,
            options: .storageModePrivate,
            name: "Shadow rays")
        rayCountBuffer = device.makeBuffer(
            type: UInt32.self,
            count: maxDepth + 1,
            options: .storageModeShared,
            name: "Ray count")
        shadowRayCountBuffer = device.makeBuffer(
            type: UInt32.self,
            count: maxDepth,
            options: .storageModeShared,
            name: "Shadow ray count")
        intersectionBuffer = device.makeBuffer(
            type: DeviceIntersection.self,
            count: rayCount,
            options: .storageModePrivate,
            name: "Intersections")
        indirectDispatchBuffer = device.makeBuffer(
            type: MTLDispatchThreadgroupsIndirectArguments.self,
            count: 1,
            options: .storageModePrivate,
            name: "Indirect dispatch")
        
        reset()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setSize(width: Int(size.width), height: Int(size.height))
    }
    
    @objc func saveFrame() {
        let path = URL.desktopDirectory.appending(path: "frame.exr")
        outputImage.saveEXR(at: path, normalizedBy: uniforms[0].accumulate ? 1 / Float(frameIndex - 1) : 1)
    }
}
