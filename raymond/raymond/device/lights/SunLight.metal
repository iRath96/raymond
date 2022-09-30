#include "../../bridge/common.hpp"
#include "../../bridge/PrngState.hpp"
#include "../../bridge/lights/SunLight.hpp"
#include "../utils/math.hpp"
#include "../lights/LightSample.hpp"
#include "../ShadingContext.hpp"
#include "../Context.hpp"

LightSample SunLight::sample(
    device Context &ctx,
    thread ShadingContext &shading,
    thread PrngState &prng
) const device {
    const float2 rnd = prng.sample2d();
    const float cosTheta = 1 - rnd.y * (1 - cosAngle);
    const float sinTheta = sqrt(saturate(1 - cosTheta * cosTheta));
    float cosPhi;
    float sinPhi = sincos(2 * M_PI_F * rnd.x, cosPhi);
    
    const float3x3 frame = buildOrthonormalBasis(direction);
    const float3 point = frame * float3(sinTheta * sinPhi, sinTheta * cosPhi, cosTheta);

    LightSample sample(info);
    sample.direction = point;
    sample.distance = INFINITY;
    
    shading.normal = -sample.direction;
    shading.trueNormal = -sample.direction;
    shading.position = -sample.direction;
    shading.generated = -sample.direction;
    shading.position = -sample.direction;
    shading.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    
    sample.weight = color;
    sample.pdf = 1;
    return sample;
}
