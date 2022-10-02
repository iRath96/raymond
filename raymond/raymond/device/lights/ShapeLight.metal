#include "../../bridge/common.hpp"
#include "../../bridge/PrngState.hpp"
#include "../../bridge/lights/SpotLight.hpp"
#include "../utils/math.hpp"
#include "../utils/warp.hpp"
#include "../lights/LightSample.hpp"
#include "../ShadingContext.hpp"
#include "../Context.hpp"

float ShapeLight::pdf(thread const ShadingContext &shading) const device {
    return 1 / (shading.geometryTerm() * emissiveArea);
}

int upper_bound(device const float *buffer, int count, float value) {
    int left = 0;
    int right = count;
    
    while (left < right) {
        int candidate = (left + right) / 2;
        if (value >= buffer[candidate]) {
            left = candidate + 1;
        } else {
            right = candidate;
        }
    }
    
    return left;
}

LightSample ShapeLight::sample(
    device Context &ctx,
    thread ShadingContext &shading,
    thread PrngState &prng
) const device {
    device const PerInstanceData &instance = ctx.perInstanceData[instanceIndex];
    
    Intersection isect;
    isect.primitiveIndex = upper_bound(
        ctx.lights.lightFaces + instance.lightFaceOffset,
        instance.lightFaceCount,
        prng.sample()
    );
    isect.coordinates = warp::uniformSquareToTriangleBarycentric(prng.sample2d());
    
    LightSample sample;
    sample.canBeHit = true;
    sample.castsShadows = true;
    
    const float3 origin = shading.position;
    shading.build(ctx, instance, isect, sample.shaderIndex);
    
    /// @todo not DRY
    sample.direction = shading.position - origin;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    sample.direction /= sample.distance;
    
    shading.wo = -sample.direction;
    shading.distance = sample.distance;
    
    const float G = shading.geometryTerm();
    sample.weight = G * emissiveArea;
    sample.pdf = 1 / (G * emissiveArea); // in solid angle
    return sample;
}
