import Foundation
import Rayjay

fileprivate let log = SwiftLogger(named: "light")

class LightBuilder {
    struct ShapeLight {
        let instanceIndex: InstanceIndex
        let faceOffset: FaceIndex
        let faceCount: FaceIndex
        let vertexOffset: VertexIndex
        let normalTransform: float3x3
        var lightIndex: LightIndex = 0
        var lightFaceOffset: FaceIndex = 0
    }
    
    struct LightCollection {
        let count: Int
        let buffer: MTLBuffer
    }
    
    private let library: [String: Light]
    private var shapeLights: [ShapeLight] = []
    private var materialBuilder: MaterialBuilder
    private var lightFaceOffset: FaceIndex = 0
    
    public init(library: [String: Light], materialBuilder: MaterialBuilder) {
        self.library = library
        self.materialBuilder = materialBuilder
        
        // request that all materials used by light sources are built
        for light in self.library.values {
            self.materialBuilder.index(of: .light, named: light.material)
        }
    }
    
    private func makeLightInfo(for light: Light) throws -> DeviceLightInfo {
        if light.useMIS && !(light.kernel is WorldLight) {
            log.warn("MIS not supported for lights yet")
        }
        
        return .init(
            shaderIndex: MaterialIndex(materialBuilder.index(of: .light, named: light.material)),
            castsShadows: light.castShadows,
            usesMIS: false // light.useMIS
        )
    }
    
    private func makeLights<Kernel: LightKernel, Output>(
        device: MTLDevice,
        closure: (DeviceLightInfo, Kernel) -> Output
    ) throws -> LightCollection {
        let lights = library.values.lazy.filter { $0.kernel is Kernel }
        let count = lights.count
        var (buffer, ptr) = device.makeBufferAndPointer(type: Output.self, count: count, name: "\(Kernel.id) Buffer")
        
        for light in lights {
            let kernel = light.kernel as! Kernel
            let info = try makeLightInfo(for: light)
            ptr.initialize(to: closure(info, kernel))
            ptr = ptr.successor()
        }
        
        return .init(count: count, buffer: buffer)
    }
    
    private func makeLights<Input, Output>(
        collection: [Input],
        device: MTLDevice,
        closure: (Input) -> Output
    ) -> LightCollection {
        let count = collection.count
        var (buffer, ptr) = device.makeBufferAndPointer(type: Output.self, count: count, name: "Light Collection Buffer")
        
        for light in collection {
            ptr.initialize(to: closure(light))
            ptr = ptr.successor()
        }
        
        return .init(count: count, buffer: buffer)
    }
    
    private func prepareEnvironmentMapSampling(
        forLibrary library: MTLLibrary,
        withContext contextBuffer: MTLBuffer,
        andEncoder contextEncoder: MTLArgumentEncoder,
        resources: inout [MTLResource],
        shaderIndex: MaterialIndex
    ) throws {
        let exponent = 11
        let resolution = 1 << exponent
        let mipmapSize = (0...exponent).map { (1 << (2 * $0)) }.reduce(0, +)
        log.debug("Building environment map of size \(resolution)^2")
        
        let device = library.device
        let mipmapBuffer = device.makeBuffer(type: Float.self, count: mipmapSize)!
        let pdfBuffer = device.makeBuffer(type: Float.self, count: resolution * resolution)!
        
        let queue = device.makeCommandQueue()!
        let commandBuffer = queue.makeCommandBuffer()!
        
        let lastLevelOffset = mipmapSize - resolution * resolution
        var bufferOffset = lastLevelOffset
        
        // MARK: build finest level of envmap
        
        let buildFunction = library.makeFunction(name: "buildEnvironmentMap")!
        let buildPipeline = try device.makeComputePipelineState(function: buildFunction)
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(buildPipeline)
            computeEncoder.setBuffer(contextBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(mipmapBuffer, offset: bufferOffset * MemoryLayout<Float>.stride, index: 1)
            computeEncoder.setBuffer(pdfBuffer, offset: 0, index: 2)
            computeEncoder.useResources(resources, usage: .read)
            computeEncoder.dispatchThreads(
                MTLSize(width: resolution, height: resolution, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            computeEncoder.endEncoding()
        }
        
        // MARK: build mipmap
        
        let reduceFunction = library.makeFunction(name: "reduceEnvironmentMap")!
        let reducePipeline = try device.makeComputePipelineState(function: reduceFunction)
        for exponent in stride(from: exponent - 1, through: 0, by: -1) {
            let currentResolution = 1 << exponent
            bufferOffset -= currentResolution * currentResolution
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(reducePipeline)
                computeEncoder.setBuffer(mipmapBuffer, offset: bufferOffset * MemoryLayout<Float>.stride, index: 0)
                computeEncoder.dispatchThreads(
                    MTLSize(width: currentResolution, height: currentResolution, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                computeEncoder.endEncoding()
            }
        }
        
        assert(bufferOffset == 0)
        
        // MARK: normalize PDFs
        
        let normalizeFunction = library.makeFunction(name: "normalizeEnvironmentMap")!
        let normalizePipeline = try device.makeComputePipelineState(function: normalizeFunction)
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(normalizePipeline)
            computeEncoder.setBuffer(mipmapBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(pdfBuffer, offset: 0, index: 1)
            computeEncoder.dispatchThreads(
                MTLSize(width: resolution * resolution, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: normalizePipeline.threadExecutionWidth, height: 1, depth: 1))
            computeEncoder.endEncoding()
        }
        
        // MARK: write out
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let envmapOffset = ContextBufferIndex.lights.rawValue + LightsBufferIndex.worldLight.rawValue
        contextEncoder.set(at: envmapOffset + 0, MaterialIndex(shaderIndex))
        contextEncoder.set(at: envmapOffset + 1, resolution)
        contextEncoder.setBuffer(pdfBuffer, offset: 0, index: envmapOffset + 2)
        contextEncoder.setBuffer(mipmapBuffer, offset: 0, index: envmapOffset + 3)
        resources.append(pdfBuffer)
        resources.append(mipmapBuffer)
    }
    
    func add(shapeLight light: ShapeLight) -> ShapeLight {
        var completed = light
        completed.lightIndex = LightIndex(shapeLights.count)
        completed.lightFaceOffset = lightFaceOffset
        lightFaceOffset += light.faceCount
        
        shapeLights.append(completed)
        return completed
    }
    
    func build(
        withDevice device: MTLDevice,
        library shadingLibrary: MTLLibrary,
        shapes: ShapeBuilder.Result,
        context: MTLBuffer,
        encoder: MTLArgumentEncoder,
        resources: inout [MTLResource]
    ) throws {
        let areaLights = try makeLights(device: device) { (info, kernel: AreaLight) in
            let normalization = kernel.isCirular ? 4 / Float.pi : 1
            return DeviceAreaLight(
                info: info,
                transform: kernel.transform,
                color: normalization * kernel.color * kernel.power,
                isCircular: kernel.isCirular)
        }
        
        let spotLights = try makeLights(device: device) { (info, kernel: SpotLight) in
            let spotAngle = cos(kernel.spotSize / 2)
            let spotBlend = (1 - spotAngle) * kernel.spotBlend
            return DeviceSpotLight(
                info: info,
                location: kernel.location,
                direction: normalize(kernel.direction),
                radius: kernel.radius,
                color: kernel.color * kernel.power,
                spotSize: spotAngle,
                spotBlend: spotBlend)
        }
        
        let pointLights = try makeLights(device: device) { (info, kernel: PointLight) in
            DevicePointLight(
                info: info,
                location: kernel.location,
                radius: kernel.radius,
                color: kernel.color * kernel.power)
        }
        
        let sunLights = try makeLights(device: device) { (info, kernel: SunLight) in
            DeviceSunLight(
                info: info,
                direction: normalize(kernel.direction),
                cosAngle: cos(kernel.angle / 2),
                color: kernel.color * kernel.power)
        }
        
        let (lightFaceBuffer, lightFaces) = device.makeBufferAndPointer(
            type: Float.self, count: Int(lightFaceOffset), name: "Light Face Buffer")
        
        let emissiveFlags = materialBuilder.getShaderNames(.surface).map(materialBuilder.hasMaterialEmission)
        let shapeLights = emissiveFlags.withUnsafeBufferPointer { emissiveFlagsPtr in
            makeLights(collection: self.shapeLights, device: device) { light in
                let emissiveArea = buildLightDistribution(
                    light.normalTransform,
                    shapes.indices.advanced(by: Int(light.faceOffset)),
                    shapes.vertices.advanced(by: Int(light.vertexOffset)),
                    shapes.materials.advanced(by: Int(light.faceOffset)),
                    emissiveFlagsPtr.baseAddress!,
                    light.faceCount,
                    lightFaces.advanced(by: Int(light.lightFaceOffset))
                )
                
                return DeviceShapeLight(
                    instanceIndex: light.instanceIndex,
                    emissiveArea: emissiveArea)
            }
        }
        
        let worldLight = library.values.first { $0.kernel is WorldLight }!
        let worldLightShader = materialBuilder.index(of: .light, named: worldLight.material)
        
        try prepareEnvironmentMapSampling(
            forLibrary: shadingLibrary,
            withContext: context,
            andEncoder: encoder,
            resources: &resources,
            shaderIndex: worldLightShader)
        
        let totalLightCount = 1 + areaLights.count + pointLights.count + sunLights.count + spotLights.count + shapeLights.count
        
        let lightsOffset = ContextBufferIndex.lights.rawValue
        encoder.set(at: lightsOffset + LightsBufferIndex.totalLightCount.rawValue, totalLightCount)
        encoder.set(at: lightsOffset + LightsBufferIndex.areaLightCount.rawValue, areaLights.count)
        encoder.set(at: lightsOffset + LightsBufferIndex.pointLightCount.rawValue, pointLights.count)
        encoder.set(at: lightsOffset + LightsBufferIndex.sunLightCount.rawValue, sunLights.count)
        encoder.set(at: lightsOffset + LightsBufferIndex.spotLightCount.rawValue, spotLights.count)
        encoder.set(at: lightsOffset + LightsBufferIndex.shapeLightCount.rawValue, shapeLights.count)
        encoder.setBuffer(areaLights.buffer, offset: 0, index: lightsOffset + LightsBufferIndex.areaLight.rawValue)
        encoder.setBuffer(pointLights.buffer, offset: 0, index: lightsOffset + LightsBufferIndex.pointLight.rawValue)
        encoder.setBuffer(sunLights.buffer, offset: 0, index: lightsOffset + LightsBufferIndex.sunLight.rawValue)
        encoder.setBuffer(spotLights.buffer, offset: 0, index: lightsOffset + LightsBufferIndex.spotLight.rawValue)
        encoder.setBuffer(shapeLights.buffer, offset: 0, index: lightsOffset + LightsBufferIndex.shapeLight.rawValue)
        resources.append(contentsOf: [
            areaLights.buffer,
            pointLights.buffer,
            sunLights.buffer,
            spotLights.buffer,
            shapeLights.buffer
        ])
        
        encoder.setBuffer(lightFaceBuffer, offset: 0, index: lightsOffset + LightsBufferIndex.lightFaces.rawValue)
        resources.append(lightFaceBuffer)
    }
}
