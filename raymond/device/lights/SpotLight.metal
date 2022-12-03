#include <bridge/common.hpp>
#include <bridge/PrngState.hpp>
#include <bridge/lights/SpotLight.hpp>
#include <device/utils/math.hpp>
#include <device/lights/LightSample.hpp>
#include <device/ShadingContext.hpp>
#include <device/Context.hpp>

float spotLightAttenuation(float3 dir, float spotAngle, float spotSmooth, float3 N) {
    float attenuation = dot(dir, N);
    if (attenuation <= spotAngle) {
        attenuation = 0.0f;
    } else {
        float t = attenuation - spotAngle;
        if (t < spotSmooth && spotSmooth != 0.0f)
            attenuation *= smoothstep(0, spotSmooth, t);
    }

    return attenuation;
}

LightSample SpotLight::sample(
    device Context &ctx,
    thread ShadingContext &shading,
    thread PrngState &prng
) const device {
    const float3 lightN = normalize(shading.position - location);
    float3 point = location;
    
    if (radius > 0) {
        float3x3 basis = buildOrthonormalBasis(lightN);
        point += radius * (basis * float3(warp::uniformSquareToDisk(prng.sample2d()), 0));
    }
    
    LightSample sample(info);
    sample.direction = point - shading.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    sample.direction /= sample.distance;
    
    shading.normal = -sample.direction;
    shading.trueNormal = -sample.direction;
    shading.position = point;
    shading.generated = point;
    shading.position = point;
    shading.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    
    const float G = 1 / lensqr;
    const float attenuation = spotLightAttenuation(direction, spotSize, spotBlend, sample.direction);
    sample.weight = attenuation * color * G * (M_1_PI_F * 0.25f);
    sample.pdf = 1;
    return sample;
}
