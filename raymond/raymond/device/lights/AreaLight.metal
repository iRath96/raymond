#include "../../bridge/lights/AreaLight.hpp"
#include "../../bridge/PrngState.hpp"
#include "../ShadingContext.hpp"
#include "../Context.hpp"
#include "LightSample.hpp"

LightSample AreaLight::sample(
    device Context &ctx,
    thread ShadingContext &shading,
    thread PrngState &prng
) const device {
    float2 uv = prng.sample2d();
    if (isCircular) {
        uv = warp::uniformSquareToDisk(uv) / 2 + 0.5;
    }
    
    const float3 point = float4(uv - 0.5, 0, 1) * transform;
    const float3 normal = normalize(float4(0, 0, 1, 0) * transform);
    
    LightSample sample(info);
    sample.direction = point - shading.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    
    shading.normal = -normal;
    shading.trueNormal = -normal;
    shading.position = point;
    shading.generated = point;
    shading.position = point;
    shading.uv = float3(uv, 0);
    
    const float G = saturate(dot(normal, sample.direction)) / lensqr;
    sample.direction /= sample.distance;
    sample.weight = color * G * 0.25f;
    sample.pdf = 1;
    return sample;
}
