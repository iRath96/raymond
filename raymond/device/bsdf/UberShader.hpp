#pragma once

#include <bridge/common.hpp>
#include "lobes/Diffuse.hpp"
#include "lobes/Specular.hpp"
#include "lobes/Transmission.hpp"
#include "lobes/Clearcoat.hpp"
#include <device/printf.hpp>

struct UberShader {
    float3 normal;
    
    float lobeProbabilities[4] = { 0, 0, 0, 0 };
    Diffuse diffuse;
    Specular specular;
    Transmission transmission;
    Clearcoat clearcoat;
    
    float alpha = 1;
    float3 alphaWeight = 1;
    
    float3 emission = 0;
    
    float weight = 1;

    bool isDelta() const {
        if (alpha < 0.5f) return true;
        if (specular.weight > 0.5f && (specular.alphaX < 0.1f || specular.alphaY < 0.1f)) return true;
        if (transmission.weight > 0.5f && (transmission.reflectionAlpha < 0.1f || transmission.transmissionAlpha < 0.1f)) return true;
        return false;
    }
    
    float3 albedo() const {
        float3 value = 0;
        if (lobeProbabilities[0] > 0) value += diffuse.diffuseWeight + diffuse.sheenWeight;
        if (lobeProbabilities[1] > 0) value += specular.weight * (specular.Cspec0 + 1) / 2;
        if (lobeProbabilities[2] > 0) value += transmission.weight * (transmission.Cspec0 + transmission.baseColor + 2) / 4;
        if (lobeProbabilities[3] > 0) value += clearcoat.weight / 4;
        value = alpha * value + (1 - alpha) * alphaWeight;
        return value + 1e-3;
    }
    
    template<bool IsLocal = false>
    float3 evaluate(float3 wo, float3 wi, float3 shNormal, float3 geoNormal, thread float &pdf) {
        /// @todo alpha? pdf and weight fields? mix/add shaders?
        pdf = 0;
        
        if (!IsLocal) {
            float3x3 worldToShadingFrame = buildOrthonormalBasis(shNormal);
            
            const float woDotGeoN = dot(wo, geoNormal);
            wo = wo * worldToShadingFrame;
            const float woDotShN = wo.z;
            if (woDotShN * woDotGeoN < 0) {
                return 0;
            }
            
            const float wiDotGeoN = dot(wi, geoNormal);
            wi = wi * worldToShadingFrame;
            const float wiDotShN = wi.z;
            if (wiDotShN * wiDotGeoN < 0) {
                return 0;
            }
        }
        
        float3 value = 0;
        float lobePdf;
        if (lobeProbabilities[0] > 0) {
            value += diffuse.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[0] * lobePdf;
        }
        if (lobeProbabilities[1] > 0) {
            value += specular.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[1] * lobePdf;
        }
        if (lobeProbabilities[2] > 0) {
            value += transmission.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[2] * lobePdf;
        }
        if (lobeProbabilities[3] > 0) {
            value += clearcoat.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[3] * lobePdf;
        }
        pdf *= alpha;
        value *= this->weight * alpha;
        return value;
    }
    
    BsdfSample sample(float3 rnd, float3 wo, float3 shNormal, float3 geoNormal, RayFlags previousFlags) {
        if (rnd.x < alpha) {
            rnd.x /= alpha;
        } else {
            BsdfSample sample;
            sample.weight = alphaWeight * weight;
            sample.wi = -wo;
            sample.pdf = 1; /// @todo hack
            sample.flags = RayFlags(previousFlags | RayFlagsSingular); /// null scattering does not alter ray flags

            return sample;
        }
        
        float3x3 worldToShadingFrame = buildOrthonormalBasis(shNormal);
        
        const float woDotGeoN = dot(wo, geoNormal);
        wo = wo * worldToShadingFrame;
        const float woDotShN = wo.z;
        if (woDotShN * woDotGeoN < 0) {
            return BsdfSample::invalid();
        }
        
        uint8_t selectedLobe;
        BsdfSample sample;
        if (rnd.x < lobeProbabilities[0]) {
            selectedLobe = 0;
            sample = diffuse.sample(rnd.yz, wo);
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1])) {
            selectedLobe = 1;
            sample = specular.sample(rnd.yz, wo);
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1] + lobeProbabilities[2])) {
            selectedLobe = 2;
            sample = transmission.sample(rnd.yz, wo);
        } else {
            selectedLobe = 3;
            sample = clearcoat.sample(rnd.yz, wo);
        }
        
        if (!isfinite(lobeProbabilities[selectedLobe]))
            /// @todo why is this needed?
            return BsdfSample::invalid();
        
        if (lobeProbabilities[selectedLobe] < 1) {
            /// For MIS, we will need an accurate PDF and value of the entire material, not just the sampled lobe
            /// @todo the efficiency of this can probably be greatly improved by not re-evaluating the already sampled lobe
            sample.weight = evaluate<true>(wo, sample.wi, shNormal, geoNormal, sample.pdf);
            sample.weight /= sample.pdf;
        } else {
            sample.pdf *= alpha;
            sample.weight *= this->weight * alpha;
        }
        
        const float wiDotShN = sample.wi.z;
        sample.wi = sample.wi * transpose(worldToShadingFrame);
        const float wiDotGeoN = dot(sample.wi, geoNormal);
        if (wiDotShN * wiDotGeoN < 0) {
            return BsdfSample::invalid();
        }
        
        return sample;
    }
};
