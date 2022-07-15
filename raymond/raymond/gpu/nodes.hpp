#pragma once

#include "bsdf.hpp"
#include "context.hpp"

#include <metal_stdlib>
using namespace metal;

struct LightPath {
    bool isDiffuseRay;
    bool isCameraRay;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        isDiffuseRay = true;
        isCameraRay = tctx.isCameraRay;
    }
};

struct VECT_MATH {
    float scale;
    float3 vector;
    float3 vector_001;
    float3 vector_002;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        // @todo implement more than just "normalize" mode
        vector = normalize(vector);
    }
};

struct NewGeometry {
    float3 normal;
    float3 tangent;
    bool backfacing;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        normal = tctx.normal;
        tangent = tctx.tu;
        backfacing = dot(tctx.wo, tctx.normal) < 0;
    }
};

struct TextureCoordinate {
    float2 uv;
    float3 normal;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        uv = tctx.uv;
        normal = tctx.normal;
    }
};

struct TexChecker {
    float scale;
    float4 color1;
    float4 color2;
    float3 vector;
    
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        int3 idx = int3(floor(vector * scale));
        color = select(color2, color1, (idx.x ^ idx.y ^ idx.z) & 1);
    }
};

struct SEPXYZ {
    float3 vector;
    float x, y, z;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        x = vector.x;
        y = vector.y;
        z = vector.z;
    }
};

struct CombineVector {
    float x, y, z;
    float3 vector;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        vector = float3(x, y, z);
    }
};

struct CombineColor {
    float red, green, blue;
    float3 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        color = float3(red, green, blue);
    }
};

struct Bump {
    float distance;
    float height;
    float3 normal;
    float strength;
    
    void compute(device Context &ctx, ThreadContext tctx) {
    }
};

struct kMapping {
    enum Type {
        TYPE_MAPPING
    };
};

template<
    kMapping::Type Type
>
struct Mapping {
    float3 scale;
    float3 rotation;
    float3 location;
    float3 vector;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        vector = euler2mat(rotation) * (vector * scale) + location;
    }
};

struct kTexImage {
    enum Interpolation {
        INTERPOLATION_LINEAR
    };
    
    enum Projection {
        PROJECTION_FLAT
    };
    
    enum Extension {
        EXTENSION_REPEAT
    };
    
    enum Alpha {
        ALPHA_STRAIGHT
    };
    
    enum PixelFormat {
        PIXEL_FORMAT_R,
        PIXEL_FORMAT_RGBA
    };
};

/**
 * Only supports "REPEAT"
 * @todo Support different sampling modes
 */
template<
    int TextureIndex,
    kTexImage::Interpolation Interpolation,
    kTexImage::Projection Projection,
    kTexImage::Extension Extension,
    kTexImage::Alpha Alpha,
    kTexImage::PixelFormat PixelFormat
>
struct TexImage {
    float3 vector;
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
        color = ctx.textures[TextureIndex].sample(
            linearSampler,
            float2(vector.x, 1 - vector.y) // weird blender convention??
        );
        
        switch (PixelFormat) {
        case kTexImage::PIXEL_FORMAT_R:
            color = float4(color.r, color.r, color.r, 1);
            break;
        
        case kTexImage::PIXEL_FORMAT_RGBA:
            break;
        }
    }
};

template<
    int NumElements
>
struct ColorRamp {
    float fac;
    float4 color;
    
    struct {
        float position;
        float4 color;
    } elements[NumElements];
    
    void compute(device Context &ctx, ThreadContext tctx) {
        if (fac < elements[0].position) {
            color = elements[0].color;
            return;
        }
        
        if (fac > elements[NumElements - 1].position) {
            color = elements[NumElements - 1].color;
            return;
        }
        
        for (int i = 1; i < NumElements; ++i) {
            if (elements[i].position >= fac) {
                auto a = elements[i - 1];
                auto b = elements[i];
                float v = (fac - a.position) / (b.position - a.position);
                color = (1 - v) * a.color + v * b.color;
                return;
            }
        }
    }
};

struct kNormalMap {
    enum Space {
        SPACE_TANGENT
    };
};

template<
    kNormalMap::Space Space
>
struct NormalMap {
    float4 color;
    float strength;
    
    float3 normal;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        float s = max(strength, 0.f);
        
        normal = normalize(2 * color.xyz - 1);
        normal = s * normal + (1 - s) * float3(0, 0, 1);
        normal = normalize(normal);
        
        float3x3 onb;
        onb[0] = tctx.tu;
        onb[1] = tctx.tv;
        onb[2] = tctx.normal;
        
        normal = onb * normal;
    }
};

/**
 * @todo only supports RGB, add support for HSV and HSL
 */
struct SeparateColor {
    float4 color;
    float red;
    float green;
    float blue;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        red = color.x;
        green = color.y;
        blue = color.z;
    }
};

struct HueSaturation {
    float4 color;
    float fac;
    float hue;
    float saturation;
    float value;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        float3 hsv = rgb2hsv(color.xyz);
        hsv.x = fmod(hsv.x + hue + 0.5, 1);
        hsv.y = saturate(hsv.y * saturation);
        hsv.z *= value;
        
        float3 result = max(hsv2rgb(hsv), 0);
        color = float4(lerp(color.xyz, result, fac), color.w);
    }
};

struct kColorMix {
    enum BlendType {
        BLEND_TYPE_MIX,
        BLEND_TYPE_ADD,
        BLEND_TYPE_MULTIPLY,
        BLEND_TYPE_SCREEN,
        BLEND_TYPE_SUB,
        BLEND_TYPE_COLOR
    };
};

template<
    kColorMix::BlendType BlendType,
    bool Clamp
>
struct ColorMix {
    float4 color1;
    float4 color2;
    float fac;
    
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        switch (BlendType) {
        case kColorMix::BLEND_TYPE_MIX:
            color = lerp(color1, color2, fac); break;
        case kColorMix::BLEND_TYPE_ADD:
            color = color1 + fac * color2; break;
        case kColorMix::BLEND_TYPE_SUB:
            color = color1 - fac * color2; break;
        case kColorMix::BLEND_TYPE_MULTIPLY:
            color = color1 * lerp(float4(1), color2, fac); break;
        case kColorMix::BLEND_TYPE_SCREEN:
            color = 1 - (1 - fac * color1) * (1 - color1); break;
        case kColorMix::BLEND_TYPE_COLOR: {
            color = color1;
            float3 hsv2 = rgb2hsv(color2.xyz);
            
            if (hsv2.y == 0) {
                color = color1;
            } else {
                float3 hsv = rgb2hsv(color1.xyz);
                hsv.xy = hsv2.xy;
                color = lerp(color1, float4(hsv2rgb(hsv), color2.a), fac);
              }

              break;
        }
        }
        
        if (Clamp) {
            color = saturate(color);
        }
    }
};

struct ColorInvert {
    float4 color;
    float fac;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        color.xyz = color.xyz - fac * (2 * color.xyz - 1);
    }
};

struct Emission {
    float4 color;
    float strength;
    float weight;
    
    Material emission;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        emission.lobeProbabilities[0] = 1;
        emission.emission = color.xyz * strength;
    }
};

struct kBsdfGlass {
    enum Distribution {
        DISTRIBUTION_GGX
    };
};

/**
 * Does not match Cycles well yet.
 */
template<
    kBsdfGlass::Distribution Distribution
>
struct BsdfGlass {
    float4 color;
    float ior;
    float3 normal;
    float roughness;
    float weight;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        const float alpha = square(max(roughness, 1e-4));
        bsdf.transmission = (Transmission){
            .reflectionAlpha = alpha,
            .transmissionAlpha = alpha,
            .baseColor = color.xyz,
            .Cspec0 = color.xyz,
            .ior = ior,
            .weight = 1
        };
        
        bsdf.lobeProbabilities[2] = 1;
        bsdf.normal = normal;
    }
};

struct kBsdfPrincipled {
    enum Distribution {
        DISTRIBUTION_GGX
    };
    
    enum SubsurfaceMethod {
        SUBSURFACE_METHOD_BURLEY
    };
};

template<
    kBsdfPrincipled::Distribution Distribution,
    kBsdfPrincipled::SubsurfaceMethod SubsurfaceMethod
>
struct BsdfPrincipled {
    float weight;
    float4 emission;
    float sheenTint;
    float emissionStrength;
    float transmission;
    float3 clearcoatNormal;
    float alpha;
    float specularTint;
    float3 tangent;
    float roughness;
    float subsurfaceIor;
    float anisotropic;
    float sheen;
    float3 subsurfaceRadius;
    float3 normal;
    float subsurfaceAnisotropy;
    float4 baseColor;
    float transmissionRoughness;
    float metallic;
    float specular;
    float clearcoatRoughness;
    float4 subsurfaceColor;
    float subsurface;
    float ior;
    float anisotropicRotation;
    float clearcoat;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        clearcoatRoughness = max(clearcoatRoughness, 1e-4);
        roughness = max(roughness, 1e-4);
        
        const float diffuseWeight = (1 - saturate(transmission)) *
            (1 - saturate(metallic));
        const float transmissionWeight = saturate(transmission) *
            (1 - saturate(metallic));
        const float specularWeight = 1 - transmissionWeight;
        
        const float luminance = dot(float3(0.2126, 0.7152, 0.0722), baseColor.xyz);
        const float3 tintColor = luminance > 0.f ?
            baseColor.xyz * (1 / luminance) :
            float3(1);
        
        const float3 sheenColor = lerp(float3(1), tintColor, sheenTint);
                
        const float3 specularColor = lerp(float3(1), tintColor, specularTint);
        const float3 Cspec0 = lerp(
            specular * 0.08 * specularColor,
            baseColor.xyz,
            metallic
        );
        
        const float aspect = sqrt(1 - 0.9 * anisotropic);
        const float r2 = square(roughness);
        
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = diffuseWeight * baseColor.xyz,
            .sheenWeight = diffuseWeight * sheen * sheenColor,
            .roughness = roughness
        };
        
        bsdf.specular = (Specular){
            .alphaX = r2 / aspect,
            .alphaY = r2 * aspect,
            .Cspec0 = Cspec0,
            .ior = (2 / (1 - sqrt(0.08 * specular))) - 1,
            .weight = specularWeight
        };
        
        bsdf.transmission = (Transmission){
            .reflectionAlpha = r2,
            .transmissionAlpha = square(
                1 - (1 - roughness) * (1 - transmissionRoughness)
            ),
            .baseColor = baseColor.xyz,
            .Cspec0 = lerp(float3(1), baseColor.xyz, specularTint),
            .ior = ior,
            .weight = transmissionWeight
        };
        
        bsdf.clearcoat = (Clearcoat){
            .alpha = square(clearcoatRoughness),
            .weight = clearcoat
        };
        
        /// @todo can be greatly improved
        bsdf.lobeProbabilities[0] = diffuseWeight;// * (luminance + sheen * 0.08);
        bsdf.lobeProbabilities[1] = specularWeight;
        bsdf.lobeProbabilities[2] = transmissionWeight;
        bsdf.lobeProbabilities[3] = clearcoat * 0.25;
        
        // normalize lobeProbabilities
        float weightsSum = 0;
        for (int i = 0; i < 4; i++) weightsSum += bsdf.lobeProbabilities[i];
        for (int i = 0; i < 4; i++) bsdf.lobeProbabilities[i] /= weightsSum;
        
        bsdf.alpha = alpha;
        bsdf.normal = normal;
    }
};

struct BsdfTransparent {
    float4 color;
    float weight;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        bsdf.alpha = 0;
        bsdf.alphaWeight = color.xyz;
    }
};

/**
 * @todo would be cool if some materials (or lobes thereof) would be mixed analytically instead of stochastically
 */
struct MixShader {
    float fac;
    Material shader;
    Material shader_001;
    
    void compute(device Context &ctx, thread ThreadContext &tctx) {
        if (tctx.rnd.x < fac) {
            tctx.rnd.x /= fac;
            shader = shader_001;
        } else {
            tctx.rnd.x = (tctx.rnd.x - fac) / (1 - fac);
        }
    }
};

struct OutputMaterial {
    float3 displacement;
    float thickness;
    Material surface;
    
    void compute(device Context &ctx, thread ThreadContext &tctx) {
        tctx.material = surface;
        //tctx.material.diffuse.diffuseWeight = float3(1, 0, 0);
    }
};

float3 VECTOR(float2 v) { return float3(v, 0); }
float3 VECTOR(float3 v) { return v; }
float3 VECTOR(float4 v) { return v.xyz; }

float4 RGBA(float v) { return float4(v, v, v, 1); }
float4 RGBA(float2 v) { return float4(v, 0, 1); }
float4 RGBA(float3 v) { return float4(v, 1); }
float4 RGBA(float4 v) { return v; }

float VALUE(float v) { return v; }
float VALUE(float3 v) { return (v.x + v.y + v.z) / 3; }
float VALUE(float4 v) { return v.w * (v.x + v.y + v.z) / 3; }

Material SHADER(Material v) { return v; }
Material SHADER(float3 v) {
    Material m;
    // @todo
    //m.type = Material::CONSTANT_COLOR;
    //m.color = v;
    return m;
}
Material SHADER(float v) { return SHADER(float3(v)); }
Material SHADER(float2 v) { return SHADER(float3(v, 0)); }
Material SHADER(float4 v) { return SHADER(v.xyz); }
