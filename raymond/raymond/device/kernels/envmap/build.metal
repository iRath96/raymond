#include <bridge/common.hpp>
#include <device/Context.hpp>

kernel void buildEnvironmentMap(
    device Context &ctx [[buffer(0)]],
    device float *mipmap [[buffer(1)]],
    device float *pdfs [[buffer(2)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 imageSize   [[threads_per_grid]]
) {
    const bool UseSecondMoment = !true;
    
    const int rayIndex = threadIndex.y * imageSize.x + threadIndex.x;
    
    float value = 0;
    int numSamples = 64;
    for (int sampleIndex = 0; sampleIndex < numSamples; sampleIndex++) {
        /// @todo this might benefit from low discrepancy sampling
        
        PrngState prng(sampleIndex, rayIndex);
        
        float2 projected = (float2(threadIndex) + prng.sample2d()) / float2(imageSize);
        float3 wo = warp::uniformSquareToSphere(projected);
        
        ShadingContext shading;
        shading.rayFlags = RayFlags(0);
        shading.rnd = prng.sample3d();
        shading.wo = -wo;
        ctx.lights.evaluateEnvironment(ctx, shading);
        
        float3 sampleValue = shading.material.emission;
        if (UseSecondMoment) {
            sampleValue = square(sampleValue);
        }
        
        value += mean(sampleValue);
    }
    
    value /= numSamples;
    if (UseSecondMoment) {
        value = sqrt(value);
    }
    value += 1e-8;
    
    const uint2 quadPosition = threadIndex / 2;
    const uint2 quadGridSize = imageSize / 2;
    const uint quadIndex = quadPosition.y * quadGridSize.x + quadPosition.x;
    const uint outputIndex = 4 * quadIndex + (threadIndex.x & 1) + 2 * (threadIndex.y & 1);
    mipmap[outputIndex] = value;
    pdfs[threadIndex.y * imageSize.x + threadIndex.x] = value;
}
