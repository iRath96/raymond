#pragma once

#include "bsdf.hpp"
#include "noise.hpp"
#include "context.hpp"

#include <metal_stdlib>
using namespace metal;

float luminance(float3 color) {
    // ITU-R standard
    return dot(float3(0.2126, 0.7152, 0.0722), color);
}

float safe_divide(float a, float b) {
  return (b != 0.0) ? a / b : 0.0;
}

/**
 * @todo not properly supported!
 */
struct LightPath {
    bool isDiffuseRay;
    bool isCameraRay;
    bool isTransmissionRay;
    bool isSingularRay;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        isDiffuseRay = true;
        isTransmissionRay = false;
        isSingularRay = false; // ???
        isCameraRay = tctx.isCameraRay;
    }
};

struct kVectorMath {
    enum Operation {
        OPERATION_ADD,
        OPERATION_SUB,
        OPERATION_MULTIPLY,
        OPERATION_NORMALIZE,
        OPERATION_SCALE
    };
};

template<
    kVectorMath::Operation Operation
>
struct VectorMath {
    float scale;
    float3 vector;
    float3 vector_001;
    float3 vector_002;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        switch (Operation) {
        case kVectorMath::OPERATION_ADD:
            vector = vector + vector_001; break;
        case kVectorMath::OPERATION_SUB:
            vector = vector - vector_001; break;
        case kVectorMath::OPERATION_MULTIPLY:
            vector = vector * vector_001; break;
        case kVectorMath::OPERATION_NORMALIZE:
            vector = normalize(vector); break;
        case kVectorMath::OPERATION_SCALE:
            vector = vector * scale; break;
        }
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

struct UVMapCoordinate {
    float2 uv;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        uv = tctx.uv;
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

struct SeparateVector {
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

struct ColorCurves {
    float4 color;
    float fac;
    
    void compute(device Context &ctx, ThreadContext tctx) {
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

struct kTexNoise {
    enum Dimension {
        DIMENSION_1D,
        DIMENSION_2D,
        DIMENSION_3D,
        DIMENSION_4D
    };
};

template<
    kTexNoise::Dimension Dimension
>
struct TexNoise {
    float detail;
    float distortion;
    float roughness;
    float scale;
    float w;
    float3 vector;
    
    float fac;
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        float3 p = this->vector * scale;
        float w = this->w * scale;
        
        switch (Dimension) {
        case kTexNoise::DIMENSION_1D:
            noiseTexture(w);
            break;
        case kTexNoise::DIMENSION_2D:
            noiseTexture(p.xy);
            break;
        case kTexNoise::DIMENSION_3D:
            noiseTexture(p);
            break;
        case kTexNoise::DIMENSION_4D:
            noiseTexture(float4(p, w));
            break;
        }
    }
    
private:
    static float random_float_offset(float seed) {
        return 100.0f + hash_float_to_float(seed) * 100.0f;
    }
    
    static float2 random_float2_offset(float seed) {
        return float2(
            100.0f + hash_float2_to_float(float2(seed, 0.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 1.0f)) * 100.0f
        );
    }
    
    static float3 random_float3_offset(float seed) {
        return float3(
            100.0f + hash_float2_to_float(float2(seed, 0.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 1.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 2.0f)) * 100.0f
        );
    }
    
    static float4 random_float4_offset(float seed) {
        return float4(
            100.0f + hash_float2_to_float(float2(seed, 0.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 1.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 2.0f)) * 100.0f,
            100.0f + hash_float2_to_float(float2(seed, 3.0f)) * 100.0f
        );
    }

    void noiseTexture(float p) {
        if (distortion != 0) {
            p += snoise(p + random_float_offset(0)) * distortion;
        }
        
        color = float4(
            fractal_noise(p, detail, roughness),
            fractal_noise(p + random_float_offset(1), detail, roughness),
            fractal_noise(p + random_float_offset(2), detail, roughness),
            1
        );
        fac = color.x;
    }
    
    void noiseTexture(float2 p) {
        if (distortion != 0) {
            p += distortion * float2(
                snoise(p + random_float2_offset(0)),
                snoise(p + random_float2_offset(1))
            );
        }
        
        color = float4(
            fractal_noise(p, detail, roughness),
            fractal_noise(p + random_float2_offset(2), detail, roughness),
            fractal_noise(p + random_float2_offset(3), detail, roughness),
            1
        );
        fac = color.x;
    }
    
    void noiseTexture(float3 p) {
        if (distortion != 0) {
            p += distortion * float3(
                snoise(p + random_float3_offset(0)),
                snoise(p + random_float3_offset(1)),
                snoise(p + random_float3_offset(2))
            );
        }
        
        color = float4(
            fractal_noise(p, detail, roughness),
            fractal_noise(p + random_float3_offset(3), detail, roughness),
            fractal_noise(p + random_float3_offset(4), detail, roughness),
            1
        );
        fac = color.x;
    }
    
    void noiseTexture(float4 p) {
        if (distortion != 0) {
            p += distortion * float4(
                snoise(p + random_float4_offset(0)),
                snoise(p + random_float4_offset(1)),
                snoise(p + random_float4_offset(2)),
                snoise(p + random_float4_offset(3))
            );
        }
        
        color = float4(
            fractal_noise(p, detail, roughness),
            fractal_noise(p + random_float4_offset(4), detail, roughness),
            fractal_noise(p + random_float4_offset(5), detail, roughness),
            1
        );
        fac = color.x;
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

struct Displacement {
    float height;
    float midlevel;
    float3 normal;
    float scale;
    
    float3 displacement;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        displacement = float3(0);
    }
};

struct Fresnel {
    float ior;
    float3 normal;
    
    float fac;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        if (all(normal == 0))
            normal = tctx.normal;
        
        float cosI = dot(tctx.wo, normal);
        bool backfacing = cosI < 0;
        float eta = max(ior, 1e-5);
        eta = select(eta, 1 / eta, backfacing);
        
        fac = fresnelDielectricCos(cosI, eta);
    }
};

struct kMath {
    enum Operation {
        OPERATION_ADD,
        OPERATION_SUBTRACT,
        OPERATION_MULTIPLY,
        OPERATION_DIVIDE,
        OPERATION_MULTIPLY_ADD
    };
};

template<
    kMath::Operation Operation,
    bool Clamp
>
struct Math {
    float value;
    float value_001;
    float value_002;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        switch (Operation) {
        case kMath::OPERATION_ADD:
            value = value + value_001; break;
        case kMath::OPERATION_SUBTRACT:
            value = value - value_001; break;
        case kMath::OPERATION_MULTIPLY:
            value = value * value_001; break;
        case kMath::OPERATION_DIVIDE:
            value = safe_divide(value, value_001); break;
        case kMath::OPERATION_MULTIPLY_ADD:
            value = value * value_001 + value_002; break;
        }
        
        if (Clamp) {
            value = saturate(value);
        }
    }
};

struct kSeparateColor {
    enum Mode {
        MODE_RGB
    };
};

template<
    kSeparateColor::Mode Mode
>
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

struct kCombineColor {
    enum Mode {
        MODE_RGB
    };
};

template<
    kCombineColor::Mode Mode
>

struct CombineColor {
    float red, green, blue;
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        color = float4(red, green, blue, 1);
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

struct BrightnessContrast {
    float bright;
    float contrast;
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        float a = 1 + contrast;
        float b = bright - contrast / 2;
        
        color = max(a * color + b, 0.f);
    }
};

struct kColorMix {
    enum BlendType {
        BLEND_TYPE_MIX,
        BLEND_TYPE_ADD,
        BLEND_TYPE_MULTIPLY,
        BLEND_TYPE_SCREEN,
        BLEND_TYPE_SUB,
        BLEND_TYPE_COLOR,
        BLEND_TYPE_LIGHTEN,
        BLEND_TYPE_DARKEN
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
        case kColorMix::BLEND_TYPE_LIGHTEN:
            color = lerp(color1, max(color1, color2), fac); break;
        case kColorMix::BLEND_TYPE_DARKEN:
            color = lerp(color1, min(color1, color2), fac); break;
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

struct Background {
    float4 color;
    float strength;
    float weight;
    
    Material background;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        background.emission = color.xyz * strength;
    }
};

static constant float blackbody_table_r[][3] = {
    {1.61919106e+03f, -2.05010916e-03f, 5.02995757e+00f},
    {2.48845471e+03f, -1.11330907e-03f, 3.22621544e+00f},
    {3.34143193e+03f, -4.86551192e-04f, 1.76486769e+00f},
    {4.09461742e+03f, -1.27446582e-04f, 7.25731635e-01f},
    {4.67028036e+03f, 2.91258199e-05f, 1.26703442e-01f},
    {4.59509185e+03f, 2.87495649e-05f, 1.50345020e-01f},
    {3.78717450e+03f, 9.35907826e-06f, 3.99075871e-01f}
};

static constant float blackbody_table_g[][3] = {
    {-4.88999748e+02f, 6.04330754e-04f, -7.55807526e-02f},
    {-7.55994277e+02f, 3.16730098e-04f, 4.78306139e-01f},
    {-1.02363977e+03f, 1.20223470e-04f, 9.36662319e-01f},
    {-1.26571316e+03f, 4.87340896e-06f, 1.27054498e+00f},
    {-1.42529332e+03f, -4.01150431e-05f, 1.43972784e+00f},
    {-1.17554822e+03f, -2.16378048e-05f, 1.30408023e+00f},
    {-5.00799571e+02f, -4.59832026e-06f, 1.09098763e+00f}
};

static constant float blackbody_table_b[][4] = {
    {5.96945309e-11f, -4.85742887e-08f, -9.70622247e-05f, -4.07936148e-03f},
    {2.40430366e-11f, 5.55021075e-08f, -1.98503712e-04f, 2.89312858e-02f},
    {-1.40949732e-11f, 1.89878968e-07f, -3.56632824e-04f, 9.10767778e-02f},
    {-3.61460868e-11f, 2.84822009e-07f, -4.93211319e-04f, 1.56723440e-01f},
    {-1.97075738e-11f, 1.75359352e-07f, -2.50542825e-04f, -2.22783266e-02f},
    {-1.61997957e-13f, -1.64216008e-08f, 3.86216271e-04f, -7.38077418e-01f},
    {6.72650283e-13f, -2.73078809e-08f, 4.24098264e-04f, -7.52335691e-01f}
};

struct Blackbody {
    float temperature;
    float4 color;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        float3 b = blackbody(temperature);
        color = float4(b / luminance(b), 1);
    }
    
private:
    // taken from blender/intern/cycles/kernels/svm/math_util.h
    float3 blackbody(float t) {
        /* Calculate color in range 800..12000 using an approximation
        * a/x+bx+c for R and G and ((at + b)t + c)t + d) for B.
        *
        * The result of this can be negative to support gamut wider than
        * than rec.709, just needs to be clamped. */

        if (t >= 12000.0f) {
            return float3(0.8262954810464208f, 0.9945080501520986f, 1.566307710274283f);
        } else if (t < 800.0f) {
            /* Arbitrary lower limit where light is very dim, matching OSL. */
            return float3(5.413294490189271f, -0.20319390035873933f, -0.0822535242887164f);
        }

        int i = (t >= 6365.0f) ? 6 :
                (t >= 3315.0f) ? 5 :
                (t >= 1902.0f) ? 4 :
                (t >= 1449.0f) ? 3 :
                (t >= 1167.0f) ? 2 :
                (t >= 965.0f)  ? 1 :
                                 0;

        constant float *r = blackbody_table_r[i];
        constant float *g = blackbody_table_g[i];
        constant float *b = blackbody_table_b[i];

        const float t_inv = 1.0f / t;
        return float3(
            r[0] * t_inv + r[1] * t + r[2],
            g[0] * t_inv + g[1] * t + g[2],
            ((b[0] * t + b[1]) * t + b[2]) * t + b[3]
        );
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

struct kBsdfGlossy {
    enum Distribution {
        DISTRIBUTION_GGX
    };
};

/**
 * @todo not tested
 */
template<
    kBsdfGlass::Distribution Distribution
>
struct BsdfGlossy {
    float4 color;
    float3 normal;
    float roughness;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        const float alpha = square(max(roughness, 1e-4));
        bsdf.specular = (Specular){
            .alphaX = alpha,
            .alphaY = alpha,
            .Cspec0 = color.xyz,
            .ior = 1.45,
            .weight = 1
        };
        
        bsdf.lobeProbabilities[1] = 1;
        bsdf.normal = normal;
    }
};

struct kBsdfPrincipled {
    enum Distribution {
        DISTRIBUTION_GGX
    };
    
    enum SubsurfaceMethod {
        SUBSURFACE_METHOD_BURLEY,
        SUBSURFACE_METHOD_RANDOM_WALK
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
        
        const float lum = luminance(baseColor.xyz);
        const float3 tintColor = lum > 0.f ?
            baseColor.xyz * (1 / lum) :
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
        bsdf.emission = emission.xyz;
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

struct BsdfDiffuse {
    float4 color;
    float3 normal;
    float roughness;
    float weight;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = color.xyz,
            .sheenWeight = 0,
            .roughness = roughness
        };
        
        bsdf.lobeProbabilities[0] = 1;
    }
};

struct BsdfTranslucent {
    float4 color;
    float3 normal;
    float weight;
    
    Material bsdf;
    
    void compute(device Context &ctx, ThreadContext tctx) {
        bsdf.alpha = 0;
        bsdf.alphaWeight = color.xyz;
    }
};

/**
 * @todo would be cool if some materials (or lobes thereof) would be mixed analytically instead of stochastically
 * @todo not working yet
 */
struct AddShader {
    Material shader;
    Material shader_001;
    
    void compute(device Context &ctx, thread ThreadContext &tctx) {
        if (tctx.rnd.x < 0.5f) {
            tctx.rnd.x /= 0.5f;
            shader = shader_001;
        } else {
            tctx.rnd.x = 2 * (tctx.rnd.x - 0.5f);
        }
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
    }
};

struct OutputWorld {
    float thickness;
    Material surface;
    
    void compute(device Context &ctx, thread ThreadContext &tctx) {
        tctx.material = surface;
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
    m.emission = v;
    return m;
}
Material SHADER(float v) { return SHADER(float3(v)); }
Material SHADER(float2 v) { return SHADER(float3(v, 0)); }
Material SHADER(float4 v) { return SHADER(v.xyz); }
