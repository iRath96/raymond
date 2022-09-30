#pragma once

#include "../../../bridge/common.hpp"
#include "../../../bridge/Ray.hpp"
#include "../../utils/math.hpp"
#include "../../utils/warp.hpp"
#include "../ShadingFrame.hpp"
#include "../fresnel.hpp"
#include "../BsdfSample.hpp"

/**
 * Matches Cycles fairly well.
 */
struct Diffuse {
    float3 diffuseWeight = 0;
    float3 sheenWeight = 0;
    float roughness;
    bool translucent = false;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        if (ShadingFrame::sameHemisphere(wi, wo) == translucent) {
            pdf = 0;
            return 0;
        }
        
        const float NdotL = abs(ShadingFrame::cosTheta(wi));
        pdf = M_1_PI_F * NdotL;
        
        const float NdotV = abs(ShadingFrame::cosTheta(wo));
        const float LdotV = dot(wi, wo);
        
        const float FL = schlickWeight(NdotL);
        const float FV = schlickWeight(NdotV);
        
        // Lambertian
        const float lambertian = (1.0f - 0.5f * FV) * (1.0f - 0.5f * FL);
        
        // Retro-reflectionconst
        const float LH2 = LdotV + 1;
        const float RR = roughness * LH2;
        const float retroReflection = RR * (FL + FV + FL * FV * (RR - 1.0f));
        
        // Sheen
        const float3 wh = normalize(wo + wi);
        const float LdotH = abs(dot(wh, wi));
        const float sheen = schlickWeight(LdotH);
        
        return pdf * (diffuseWeight * (lambertian + retroReflection) +
            sheenWeight * (M_PI_F * sheen));
    }
    
    BsdfSample sample(float2 rnd, float3 wo) {
        BsdfSample result;
        result.wi = warp::uniformSquareToCosineWeightedHemisphere(rnd);
        if (!ShadingFrame::sameHemisphere(result.wi, wo)) {
            result.wi *= -1;
        }
        
        const float NdotL = abs(ShadingFrame::cosTheta(result.wi));
        result.pdf = M_1_PI_F * NdotL;
        
        if (!(result.pdf > 0))
            return BsdfSample::invalid();
        
        const float NdotV = abs(ShadingFrame::cosTheta(wo));
        const float LdotV = dot(result.wi, wo);
        
        const float FL = schlickWeight(NdotL);
        const float FV = schlickWeight(NdotV);
        
        // Lambertian
        const float lambertian = (1.0f - 0.5f * FV) * (1.0f - 0.5f * FL);
        
        // Retro-reflectionconst
        const float LH2 = LdotV + 1;
        const float RR = roughness * LH2;
        const float retroReflection = RR * (FL + FV + FL * FV * (RR - 1.0f));
        
        // Sheen
        const float3 wh = normalize(wo + result.wi);
        const float LdotH = abs(dot(wh, result.wi));
        const float sheen = schlickWeight(LdotH);
        
        result.weight = diffuseWeight * (lambertian + retroReflection) +
            sheenWeight * (M_PI_F * sheen);
        
        if (translucent) {
            result.wi = -result.wi;
            result.flags = RayFlags(RayFlagsTransmission | RayFlagsDiffuse);
        } else {
            result.flags = RayFlags(RayFlagsReflection | RayFlagsDiffuse);
        }
        
        return result;
    }
};
