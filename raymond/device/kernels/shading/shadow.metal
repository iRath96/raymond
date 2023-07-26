#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/ResourceIds.hpp>
#include <device/utils/math.hpp>

kernel void handleShadowRays(
    texture2d<float, access::read_write> image [[texture(0)]],
    
    device const Intersection *intersections [[buffer(ShadowBufferIntersections)]],
    device const ShadowRay *shadowRays [[buffer(ShadowBufferShadowRays)]],
    device const uint &rayCount [[buffer(ShadowBufferRayCount)]],
    
    const uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= rayCount)
        return;
    
    device const ShadowRay &shadowRay = shadowRays[rayIndex];
    
    device const Intersection &isect = intersections[rayIndex];
    if (isect.distance < 0.0f)
    {
        uint2 coordinates = uint2(shadowRay.x, shadowRay.y);
        image.write(
            image.read(coordinates) + float4(shadowRay.weight, 1),
            coordinates
        );
    }
}
