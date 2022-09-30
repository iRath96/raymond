#pragma once

#include "../../../bridge/common.hpp"
#include "../../../bridge/Ray.hpp"
#include "../../utils/math.hpp"
#include "../../utils/warp.hpp"
#include "../ShadingFrame.hpp"
#include "../fresnel.hpp"
#include "../microfacet.hpp"
#include "../BsdfSample.hpp"

/**
 * Not perfect yet: failure case for clearcoatRoughness=0.3.
 */
struct Clearcoat {
    float alpha;
    float weight = 0;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        const float3 wh = normalize(wi + wo);
        
        // VNDF PDF
        pdf = anisotropicGGX(wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        if (!(pdf > 0)) {
            pdf = 0;
            return 0;
        }
        
        pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(wi, wh, 1.5, float3(0.04));
        const float3 G = anisotropicSmithG1(wi, wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha);
        const float3 D = anisotropicGGX(wh, alpha, alpha);
        return 0.25 * F * D * G / abs(4 * ShadingFrame::cosTheta(wo));
    }
    
    BsdfSample sample(float2 rnd, float3 wo) {
        BsdfSample result;
        
        const float3 wh = sampleGGXVNDF(rnd, alpha, alpha, wo);
        result.pdf = anisotropicGGX(wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        
        if (!(result.pdf > 0))
            return BsdfSample::invalid();
        
        result.wi = reflect(-wo, wh);
        if (!ShadingFrame::sameHemisphere(result.wi, wo))
            return BsdfSample::invalid();
        
        result.pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(result.wi, wh, 1.5, float3(0.04));
        const float Gi = smithG1(result.wi, wh, alpha);
        result.weight = 0.25 * weight * F * Gi;
        result.flags = RayFlags(RayFlagsReflection | RayFlagsGlossy); /// @todo RayFlagsSingular
        return result;
    }
};
