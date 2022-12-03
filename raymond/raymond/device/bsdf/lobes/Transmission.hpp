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
 * Not perfect yet: failure case for high values of transmissionRoughness, also Fresnel does not seem to match well.
 */
struct Transmission {
    float reflectionAlpha;
    float transmissionAlpha;
    float3 baseColor;
    float3 Cspec0;
    float ior;
    float weight = 0;
    bool onlyRefract = false;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        const bool isReflection = ShadingFrame::sameHemisphere(wi, wo);
        if (onlyRefract && isReflection) {
            pdf = 0;
            return 0;
        }
        
        const float eta = ShadingFrame::cosTheta(wo) > 0 ? ior : 1 / ior;
        
        const float3 wh = isReflection ?
            normalize(wi + wo) :
            normalize(wi * eta + wo);
        
        const float alpha = isReflection ?
            reflectionAlpha :
            transmissionAlpha;
        
        // VNDF PDF
        pdf = anisotropicGGX(wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        if (!(pdf > 0)) {
            pdf = 0;
            return 0;
        }
        
        const float Gi = anisotropicSmithG1(wi, wh, alpha, alpha);
        const float Fr = onlyRefract ? 0 : fresnelDielectricCos(ShadingFrame::cosTheta(wo), eta);
        if (isReflection) {
            pdf *= Fr;
            pdf *= 1 / abs(4 * dot(wo, wh));
            
            const float3 F = fresnelReflectionColor(wi, wh, eta, Cspec0);
            return pdf * weight * F * Gi;
        } else {
            pdf *= 1 - Fr;
            pdf *= abs(dot(wi, wh) / square(dot(wi, wh) + dot(wh, wo) / eta));
            
            return pdf * weight * baseColor * Gi;
        }
    }
    
    BsdfSample sample(float2 rnd, float3 wo) {
        BsdfSample result;
        
        float eta = ShadingFrame::cosTheta(wo) > 0 ? ior : 1 / ior;
        const float Fr = onlyRefract ? 0 : fresnelDielectricCos(ShadingFrame::cosTheta(wo), eta);
        const bool isReflection = rnd.x < Fr;
        
        const float alpha = isReflection ?
            reflectionAlpha :
            transmissionAlpha;
        
        const float3 wh = sampleGGXVNDF(rnd, alpha, alpha, wo);
        result.pdf = anisotropicGGX(wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        
        if (isReflection) {
            // reflect
            rnd.x /= Fr;
            
            if (!(result.pdf > 0))
                return BsdfSample::invalid();
            
            result.wi = reflect(-wo, wh);
            if (!ShadingFrame::sameHemisphere(result.wi, wo))
                return BsdfSample::invalid();
            
            result.pdf *= Fr;
            result.pdf *= 1 / abs(4 * dot(wo, wh));
            
            const float3 F = fresnelReflectionColor(result.wi, wh, eta, Cspec0);
            const float Gi = anisotropicSmithG1(result.wi, wh, alpha, alpha);
            result.weight = weight * F * Gi;
            result.flags = RayFlags(RayFlagsReflection | RayFlagsGlossy); /// @todo RayFlagsSingular
            return result;
        } else {
            // refract
            rnd.x = (rnd.x - Fr) / (1 - Fr);
            
            if (!(result.pdf > 0))
                return BsdfSample::invalid();
            
            //result.wi = (dot(wh, wo) / eta - cosThetaT) * wh - wo / eta;
            result.wi = refract(-wo, wh, 1/eta);
            if (ShadingFrame::sameHemisphere(result.wi, wo))
                return BsdfSample::invalid();
            
            result.pdf *= 1 - Fr;
            result.pdf *= abs(dot(result.wi, wh) / square(dot(result.wi, wh) + dot(wh, wo) / eta));
            
            //const float3 F = fresnelReflectionColor(result.wi, wh, eta, Cspec0);
            const float Gi = anisotropicSmithG1(result.wi, wh, alpha, alpha);
            result.weight = weight * baseColor * Gi;
            result.flags = RayFlags(RayFlagsTransmission | RayFlagsGlossy); /// @todo RayFlagsSingular
            return result;
        }
    }
};
