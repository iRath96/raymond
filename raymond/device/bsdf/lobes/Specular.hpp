#pragma once

#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <device/utils/math.hpp>
#include <device/utils/warp.hpp>
#include <device/bsdf/ShadingFrame.hpp>
#include <device/bsdf/fresnel.hpp>
#include <device/bsdf/microfacet.hpp>
#include <device/bsdf/BsdfSample.hpp>

/**
 * Matches Cycles fairly well.
 */
struct Specular {
    float alphaX;
    float alphaY;
    float3 Cspec0;
    float ior;
    float weight = 0;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        const float3 wh = normalize(wi + wo);
        
        // VNDF PDF
        pdf = anisotropicGGX(wh, alphaX, alphaY) *
            anisotropicSmithG1(wo, wh, alphaX, alphaY) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        if (!(pdf > 0)) {
            pdf = 0;
            return 0;
        }
        
        pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(wi, wh, ior, Cspec0);
        const float3 G = anisotropicSmithG1(wi, wh, alphaX, alphaY) *
            anisotropicSmithG1(wo, wh, alphaX, alphaY);
        const float3 D = anisotropicGGX(wh, alphaX, alphaY);
        return F * D * G / abs(4 * ShadingFrame::cosTheta(wo));
    }
    
    BsdfSample sample(float2 rnd, float3 wo) {
        BsdfSample result;
        
        const float3 wh = sampleGGXVNDF(rnd, alphaX, alphaY, wo);
        result.pdf = anisotropicGGX(wh, alphaX, alphaY) *
            anisotropicSmithG1(wo, wh, alphaX, alphaY) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        
        if (!(result.pdf > 0))
            return BsdfSample::invalid();
        
        result.wi = reflect(-wo, wh);
        if (!ShadingFrame::sameHemisphere(result.wi, wo))
            return BsdfSample::invalid();
        
        result.pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(result.wi, wh, ior, Cspec0);
        const float Gi = anisotropicSmithG1(result.wi, wh, alphaX, alphaY);
        result.weight = weight * F * Gi;
        result.flags = RayFlags(RayFlagsReflection | RayFlagsGlossy); /// @todo RayFlagsSingular
        return result;
    }
};
