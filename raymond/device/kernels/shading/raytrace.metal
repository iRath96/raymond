#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/ResourceIds.hpp>
#include <bridge/PrngState.hpp>
#include <bridge/Uniforms.hpp>
#include <device/Context.hpp>
#include <device/utils/color.hpp>
#include <device/printf.hpp>

using namespace metal::raytracing;
kernel void raytrace(
    device Ray *rays                        [[buffer(GeneratorBufferRays)]],
    device uint &rayCount                   [[buffer(GeneratorBufferRayCount)]],
    device Intersection *intersections      [[buffer(GeneratorBufferIntersections)]],
    instance_acceleration_structure accel   [[buffer(GeneratorBufferAccelerationStructure)]],
    uint rayIndex                           [[thread_position_in_grid]]
) {
    if (rayIndex >= rayCount)
        return;
    
    const device Ray &ray = rays[rayIndex];

    // Create an intersector to test for intersection between the ray and the geometry in the scene.
    intersector<triangle_data, instancing> i;
    bool useIntersectionFunctions = false;

    // If the sample isn't using intersection functions, provide some hints to Metal for
    // better performance.
    if (!useIntersectionFunctions) {
        i.assume_geometry_type(geometry_type::triangle);
        i.force_opacity(forced_opacity::opaque);
    }
    
    i.accept_any_intersection(false);
    
    metal::raytracing::ray mtlRay;
    mtlRay.origin = ray.origin;
    mtlRay.direction = ray.direction;
    mtlRay.min_distance = ray.minDistance;
    mtlRay.max_distance = ray.maxDistance;
    
    auto mtlIsect = i.intersect(mtlRay, accel);
    intersections[rayIndex].distance = mtlIsect.distance;
    intersections[rayIndex].coordinates = float2(
        1 - mtlIsect.triangle_barycentric_coord.x - mtlIsect.triangle_barycentric_coord.y,
        mtlIsect.triangle_barycentric_coord.x
    );
    intersections[rayIndex].instanceIndex = mtlIsect.instance_id;
    intersections[rayIndex].primitiveIndex = mtlIsect.primitive_id;
}

kernel void raytraceAny(
    device ShadowRay *rays                  [[buffer(GeneratorBufferRays)]],
    device uint &rayCount                   [[buffer(GeneratorBufferRayCount)]],
    device Intersection *intersections      [[buffer(GeneratorBufferIntersections)]],
    instance_acceleration_structure accel   [[buffer(GeneratorBufferAccelerationStructure)]],
    uint rayIndex                           [[thread_position_in_grid]]
) {
    if (rayIndex >= rayCount)
        return;
    
    const device ShadowRay &ray = rays[rayIndex];

    // Create an intersector to test for intersection between the ray and the geometry in the scene.
    intersector<triangle_data, instancing> i;
    bool useIntersectionFunctions = false;

    // If the sample isn't using intersection functions, provide some hints to Metal for
    // better performance.
    if (!useIntersectionFunctions) {
        i.assume_geometry_type(geometry_type::triangle);
        i.force_opacity(forced_opacity::opaque);
    }
    
    i.accept_any_intersection(true);
    
    metal::raytracing::ray mtlRay;
    mtlRay.origin = ray.origin;
    mtlRay.direction = ray.direction;
    mtlRay.min_distance = ray.minDistance;
    mtlRay.max_distance = ray.maxDistance;
    
    auto mtlIsect = i.intersect(mtlRay, accel);
    intersections[rayIndex].distance = mtlIsect.distance;
}
