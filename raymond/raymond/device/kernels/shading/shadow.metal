#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/ResourceIds.hpp>
#include <device/utils/math.hpp>

kernel void handleShadowRays(
    texture2d<float, access::read_write> image [[texture(0)]],
    
    constant Intersection *intersections [[buffer(ShadowBufferIntersections)]],
    device ShadowRay *shadowRays [[buffer(ShadowBufferShadowRays)]],
    device const uint &rayCount [[buffer(ShadowBufferRayCount)]],
    
    uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= rayCount)
        return;
    
    device ShadowRay &shadowRay = shadowRays[rayIndex];
    
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance < 0.0f)
    {
        uint2 coordinates = uint2(shadowRay.x, shadowRay.y);
        image.write(
            image.read(coordinates) + float4(shadowRay.weight, 1),
            coordinates
        );
    }
}
