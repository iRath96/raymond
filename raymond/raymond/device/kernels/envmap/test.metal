#include "../../../bridge/common.hpp"
#include "../../../bridge/PrngState.hpp"
#include "../../utils/warp.hpp"
#include "../../Context.hpp"

kernel void testEnvironmentMapSampling(
    device Context &ctx [[buffer(0)]],
    device atomic_float *histogram [[buffer(1)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 gridSize [[threads_per_grid]]
) {
    PrngState prng(threadIndex.x, threadIndex.y);
    
    const int outputResolution = 256;
    
    const float norm = outputResolution * outputResolution / float(gridSize.x * gridSize.y);
    //const float2 uv = prng.sample2d();
    const float2 uv = (float2(threadIndex) + prng.sample2d()) / float2(gridSize);
    //const float3 sample = warp::uniformSquareToSphere(uv);
    
    float samplePdf;
    const float3 sample = ctx.lights.worldLight.sample(uv, samplePdf);
    const float2 projected = warp::uniformSphereToSquare(sample);
    const float pdf = 1;//ctx.envmap.pdf(sample) * (4 * M_PI_F);
    
    const uint2 outputPos = uint2(projected * outputResolution) % outputResolution;
    const int outputIndex = outputPos.y * outputResolution + outputPos.x;
    atomic_fetch_add_explicit(histogram + outputIndex, norm / pdf, memory_order_relaxed);
}
