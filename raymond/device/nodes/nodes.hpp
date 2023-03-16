#pragma once

#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <device/utils/noise.hpp>
#include <device/utils/math.hpp>
#include <device/utils/warp.hpp>
#include <device/utils/color.hpp>
#include <device/Context.hpp>
#include <device/ShadingContext.hpp>

/**
 * @todo not properly supported!
 */
struct LightPath {
    bool isCameraRay;
    bool isReflectionRay;
    bool isTransmissionRay;
    bool isShadowRay;
    
    bool isDiffuseRay;
    bool isGlossyRay;
    bool isSingularRay;
    
    float rayLength;
    
    void compute(device Context &ctx, ShadingContext shading) {
        isCameraRay       = (shading.rayFlags & RayFlagsCamera) > 0;
        isReflectionRay   = (shading.rayFlags & RayFlagsReflection) > 0;
        isTransmissionRay = (shading.rayFlags & RayFlagsTransmission) > 0;
        isShadowRay       = (shading.rayFlags & RayFlagsShadow) > 0;
        
        isDiffuseRay  = (shading.rayFlags & RayFlagsDiffuse) > 0;
        isGlossyRay   = (shading.rayFlags & RayFlagsGlossy) > 0;
        isSingularRay = (shading.rayFlags & RayFlagsSingular) > 0;
        
        rayLength = shading.distance; /// @todo verify
        
        if (isSingularRay)
            /// @todo verify
            isGlossyRay = true;
    }
};

/**
 * @todo not properly supported!
 */
struct ObjectInfo {
    int objectIndex;
    float random; /// @todo unsupported
    float3 location; /// @todo unsupported
    
    void compute(device Context &ctx, ShadingContext shading) {}
};

/**
 * @todo not supported!
 */
struct AmbientOcclusion {
    float4 color;
    float distance;
    float3 normal;
    
    float ao;
    
    void compute(device Context &ctx, ShadingContext shading) {
        ao = 1;
    }
};

/**
 * @todo not supported!
 */
struct VolumeScatter {
    float anisotropy;
    float4 color;
    float density;
    float weight;
    
    UberShader volume;
    
    void compute(device Context &ctx, ShadingContext shading) {}
};

/**
 * @todo not properly supported!
 */
struct ParticleInfo {
    float random; /// @todo unsupported

    void compute(device Context &ctx, ShadingContext shading) {}
};

/**
 * @todo not properly supported!
 */
struct LightFalloff {
    float strength;
    float smooth;
    float quadratic;
    
    void compute(device Context &ctx, ShadingContext shading) {
        quadratic = 1; /// @todo
    }
};

/**
 * @todo not properly supported!
 */
struct VertexColor {
    float3 color; /// @todo unsupported

    void compute(device Context &ctx, ShadingContext shading) {
        
    }
};

struct kVectorMath {
    enum Operation {
        OPERATION_ADD,
        OPERATION_SUBTRACT,
        OPERATION_MULTIPLY,
        OPERATION_MULTIPLY_ADD,
        OPERATION_NORMALIZE,
        OPERATION_SCALE,
        OPERATION_MINIMUM,
        OPERATION_LENGTH,
        OPERATION_DOT_PRODUCT
    };
};

template<
    kVectorMath::Operation Operation
>
struct VectorMath {
    float scale;
    
    float value;
    float3 vector;
    float3 vector_001;
    float3 vector_002;
    
    void compute(device Context &ctx, ShadingContext shading) {
        switch (Operation) {
        case kVectorMath::OPERATION_ADD:
            vector = vector + vector_001; break;
        case kVectorMath::OPERATION_SUBTRACT:
            vector = vector - vector_001; break;
        case kVectorMath::OPERATION_MULTIPLY:
            vector = vector * vector_001; break;
        case kVectorMath::OPERATION_MULTIPLY_ADD:
            vector = vector * vector_001 + vector_002; break;
        case kVectorMath::OPERATION_NORMALIZE:
            vector = normalize(vector); break;
        case kVectorMath::OPERATION_SCALE:
            vector = vector * scale; break;
        case kVectorMath::OPERATION_MINIMUM:
            vector = min(vector, vector_001); break;
        case kVectorMath::OPERATION_LENGTH:
            value = length(vector); break;
        case kVectorMath::OPERATION_DOT_PRODUCT:
            /// @todo verify
            vector = dot(vector, vector_001); break;
        }
    }
};

struct NewGeometry {
    float3 normal;
    float3 trueNormal;
    float3 tangent;
    float3 position;
    float3 parametric; /// @todo apparently this is different to "Texture"."UV"
    float3 incoming; /// @todo not tested
    float3 randomPerIsland; /// @todo unsupported
    bool backfacing;
    
    void compute(device Context &ctx, ShadingContext shading) {
        normal = shading.normal;
        trueNormal = shading.trueNormal;
        tangent = shading.tu;
        position = shading.position;
        parametric = shading.uv;
        incoming = shading.wo;
        randomPerIsland = 0;
        backfacing = dot(shading.wo, shading.normal) < 0;
    }
};

struct TextureCoordinate {
    float3 generated;
    float3 uv;
    float3 object;
    float3 normal;
    float3 reflection;
    
    void compute(device Context &ctx, ShadingContext shading) {
        uv = shading.uv;
        generated = shading.generated;
        object = shading.object;
        normal = shading.normal;
        reflection = shading.normal; /// @todo
    }
};

struct UVMapCoordinate {
    float3 uv;
    
    void compute(device Context &ctx, ShadingContext shading) {
        uv = shading.uv;
    }
};

struct TexChecker {
    float scale;
    float4 color1;
    float4 color2;
    float3 vector;
    
    float fac;
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        float3 p = (vector * scale + 0.000001f) * 0.999999f;
        int3 idx = int3(floor(p));
        
        const bool which = (idx.x ^ idx.y ^ idx.z) & 1;
        color = select(color2, color1, which);
        fac = select(0.f, 1.f, which);
    }
};

struct SeparateVector {
    float3 vector;
    float x, y, z;
    
    void compute(device Context &ctx, ShadingContext shading) {
        x = vector.x;
        y = vector.y;
        z = vector.z;
    }
};

struct CombineVector {
    float x, y, z;
    float3 vector;
    
    void compute(device Context &ctx, ShadingContext shading) {
        vector = float3(x, y, z);
    }
};

struct ColorCurves {
    float4 color;
    float fac;
    
    void compute(device Context &ctx, ShadingContext shading) {
    }
};

struct Bump {
    float distance;
    float height;
    float3 normal;
    float strength;
    
    void compute(device Context &ctx, ShadingContext shading) {
    }
};

struct kMapRange {
    enum DataType {
        DATA_TYPE_FLOAT
    };
    
    enum InterpolationType {
        INTERPOLATION_TYPE_LINEAR
    };
};

template<
    bool Clamp,
    kMapRange::DataType DataType,
    kMapRange::InterpolationType InterpolationType
>
struct MapRange {
    float fromMin;
    float fromMax;
    float toMin;
    float toMax;
    
    float steps;
    float3 steps_Float3;
    
    float3 from_Min_Float3;
    float3 from_Max_Float3;
    float3 to_Min_Float3;
    float3 to_Max_Float3;
    
    float value;
    float3 vector;
    
    float result;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo not tested
        float v = (value - fromMin) / (fromMax - fromMin);
        if (Clamp) v = saturate(v);
        result = lerp(toMin, toMax, v);
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        vector = euler2mat(rotation) * (vector * scale) + location;
    }
};

struct kTexGradient {
    enum Type {
        TYPE_LINEAR,
        TYPE_SPHERICAL
    };
};

template<
    kTexGradient::Type Type
>
struct TexGradient {
    float3 vector;
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        switch (Type) {
        case kTexGradient::TYPE_LINEAR:
            color = saturate(vector.x);
            break;
        
        case kTexGradient::TYPE_SPHERICAL:
            color = saturate(length(vector));
            break;
        }
    }
};

struct kTexWave {
    enum Type {
        TYPE_BANDS
    };
    
    enum Direction {
        DIRECTION_DIAGONAL
    };
    
    enum Profile {
        PROFILE_SIN
    };
};

template<
    kTexWave::Type Type,
    kTexWave::Direction Direction,
    kTexWave::Profile Profile
>
struct TexWave {
    float detail;
    float detailRoughness;
    float detailScale;
    float distortion;
    float phaseOffset;
    float scale;
    float3 vector;
    
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        color = 1; /// @todo
    }
};

struct kTexImage {
    enum Interpolation {
        INTERPOLATION_LINEAR
    };
    
    enum Projection {
        // TexImage
        PROJECTION_FLAT,
        PROJECTION_BOX,
        
        // TexEnvironment
        PROJECTION_EQUIRECTANGULAR,
        
        PROJECTION_MIRROR_BALL
    };
    
    enum Extension {
        EXTENSION_REPEAT
    };
    
    enum Alpha {
        ALPHA_STRAIGHT
    };
    
    enum ColorSpace {
        COLOR_SPACE_LINEAR,
        COLOR_SPACE_SRGB,
        COLOR_SPACE_NON_COLOR,
        COLOR_SPACE_RAW,
        COLOR_SPACE_XYZ,
        COLOR_SPACE_FILMIC_LOG
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
    kTexImage::ColorSpace ColorSpace,
    kTexImage::PixelFormat PixelFormat
>
struct TexImage {
    float3 vector;
    float4 color;
    float alpha;
    
    void compute(device Context &ctx, ShadingContext shading) {
        float2 projected;
        switch (Projection) {
        case kTexImage::PROJECTION_FLAT:
            projected = float2(vector.x, 1 - vector.y);
            break;
        
        case kTexImage::PROJECTION_EQUIRECTANGULAR:
            projected = warp::equirectSphereToSquare(vector);
            break;
        
        case kTexImage::PROJECTION_BOX:
        case kTexImage::PROJECTION_MIRROR_BALL:
            /// @todo not implemented
            break;
        }
        
        constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
        color = ctx.textures[TextureIndex].sample(linearSampler, projected);
        alpha = color.w;
        
        switch (PixelFormat) {
        case kTexImage::PIXEL_FORMAT_R:
            color = float4(color.r, color.r, color.r, 1);
            break;
        
        case kTexImage::PIXEL_FORMAT_RGBA:
            break;
        }
        
        switch (ColorSpace) {
        case kTexImage::COLOR_SPACE_LINEAR:
            break;
        
        case kTexImage::COLOR_SPACE_SRGB:
            color.xyz = float3(
                srgb_to_linearrgb(color.x),
                srgb_to_linearrgb(color.y),
                srgb_to_linearrgb(color.z)
            );
            break;
        
        case kTexImage::COLOR_SPACE_RAW:
        case kTexImage::COLOR_SPACE_NON_COLOR:
        case kTexImage::COLOR_SPACE_FILMIC_LOG:
            /// @todo what is this?
            break;
        
        case kTexImage::COLOR_SPACE_XYZ:
            /// @todo verify
            color.xyz = xyz_to_rgb(color.xyz);
            break;
        }
    }
    
private:
    // taken from blender/blenkernel/intern/studiolight.c
    float srgb_to_linearrgb(float c) {
        if (c < 0.04045f) {
            return (c < 0.0f) ? 0.0f : c * (1.0f / 12.92f);
        }

        return pow((c + 0.055f) * (1.0f / 1.055f), 2.4f);
    }
};

struct TexIES {
    float3 vector;
    float strength;
    float fac;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo
        fac = strength;
    }
};

struct TexMagic {
    float distortion;
    float scale;
    float3 vector;
    
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo
        color = 1;
    }
};

struct TexVoronoi {
    float exponent;
    float randomness;
    float scale;
    float smoothness;
    float3 vector;
    float w;
    
    float4 color;
    float distance;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo
        color = 1;
        distance = 0;
    }
};

struct TexMusgrave {
    float detail;
    float dimension;
    float gain;
    float lacunarity;
    float offset;
    float scale;
    float w;
    float3 vector;
    
    float fac;
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo unsupported
        fac = 1;
        color = 1;
    }
};

struct TexBrick {
    float4 color1, color2, mortar;
    float bias;
    float brickWidth;
    float mortarSize;
    float mortarSmooth;
    float rowHeight;
    float scale;
    float3 vector;
    
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo unsupported
        color = 1;
    }
};

struct kTexEnvironment {
    enum Interpolation {
        INTERPOLATION_LINEAR
    };
    
    enum Projection {
        PROJECTION_EQUIRECTANGULAR
    };
    
    enum Alpha {
        ALPHA_STRAIGHT
    };
    
    enum ColorSpace {
        COLOR_SPACE_LINEAR,
        COLOR_SPACE_SRGB,
        COLOR_SPACE_NON_COLOR,
        COLOR_SPACE_XYZ
    };
    
    enum PixelFormat {
        PIXEL_FORMAT_R,
        PIXEL_FORMAT_RGBA
    };
};

// taken from blender/intern/cycles/kernel/osl/shaders/node_sky_texture.osl

float sky_angle_between(float thetav, float phiv, float theta, float phi) {
    float cospsi = sin(thetav) * sin(theta) * cos(phi - phiv) + cos(thetav) * cos(theta);

    if (cospsi > 1.0)
        return 0.0;
    if (cospsi < -1.0)
        return M_PI_F;

    return acos(cospsi);
}

float2 sky_spherical_coordinates(float3 dir) {
    return float2(acos(dir.z), atan2(dir.x, dir.y));
}

/* Preetham */
float sky_perez_function(float lam[9], float theta, float gamma) {
    float ctheta = cos(theta);
    float cgamma = cos(gamma);

    return (1.0 + lam[0] * exp(lam[1] / ctheta)) *
           (1.0 + lam[2] * exp(lam[3] * gamma) + lam[4] * cgamma * cgamma);
}

float3 sky_radiance_preetham(
    float3 dir,
    float sunphi,
    float suntheta,
    float3 radiance,
    float config_x[9],
    float config_y[9],
    float config_z[9]
) {
    /* convert vector to spherical coordinates */
    float2 spherical = sky_spherical_coordinates(dir);
    float theta = spherical.x;
    float phi = spherical.y;

    /* angle between sun direction and dir */
    float gamma = sky_angle_between(theta, phi, suntheta, sunphi);

    /* clamp theta to horizon */
    theta = min(theta, M_PI_2_F - 0.001f);

    /* compute xyY color space values */
    float x = radiance.y * sky_perez_function(config_y, theta, gamma);
    float y = radiance.z * sky_perez_function(config_z, theta, gamma);
    float Y = radiance.x * sky_perez_function(config_x, theta, gamma);

    /* convert to RGB */
    float3 xyz = xyY_to_xyz(x, y, Y);
    return xyz_to_rgb(xyz);
}

/* Hosek / Wilkie */
float sky_radiance_internal(float config[9], float theta, float gamma) {
    float ctheta = cos(theta);
    float cgamma = cos(gamma);

    float expM = exp(config[4] * gamma);
    float rayM = cgamma * cgamma;
    float mieM = (1.0 + rayM) / pow((1.0 + config[8] * config[8] - 2.0 * config[8] * cgamma), 1.5);
    float zenith = sqrt(ctheta);

    return (1.0 + config[0] * exp(config[1] / (ctheta + 0.01))) *
           (config[2] + config[3] * expM + config[5] * rayM + config[6] * mieM + config[7] * zenith);
}

float3 sky_radiance_hosek(
    float3 dir,
    float sunphi,
    float suntheta,
    float3 radiance,
    float config_x[9],
    float config_y[9],
    float config_z[9]
) {
    /* convert vector to spherical coordinates */
    float2 spherical = sky_spherical_coordinates(dir);
    float theta = spherical.x;
    float phi = spherical.y;

    /* angle between sun direction and dir */
    float gamma = sky_angle_between(theta, phi, suntheta, sunphi);

    /* clamp theta to horizon */
    theta = min(theta, M_PI_2_F - 0.001f);

    /* compute xyz color space values */
    float3 xyz = sky_radiance_internal(config_x, theta, gamma) * radiance;

    /* convert to RGB and adjust strength */
    return xyz_to_rgb(xyz) * (2 * M_PI_F / 683);
}

/* Nishita improved */
float3 geographical_to_direction(float lat, float lon) {
    return float3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat));
}

float precise_angle(float3 a, float3 b) {
    return 2.f * atan2(length(a - b), length(a + b));
}

float3 sky_radiance_nishita(float3 dir, float nishita_data[10], texture2d<float> texture) {
  /* definitions */
  float sun_elevation = nishita_data[6];
  float sun_rotation = nishita_data[7];
  float angular_diameter = nishita_data[8];
  float sun_intensity = nishita_data[9];
  int sun_disc = angular_diameter > 0;
  float3 xyz = float3(0, 0, 0);
  /* convert dir to spherical coordinates */
  float2 direction = sky_spherical_coordinates(dir);

  /* render above the horizon */
  if (dir.z >= 0.0) {
    /* definitions */
    float3 sun_dir = geographical_to_direction(sun_elevation, sun_rotation + M_PI_2_F);
    float sun_dir_angle = precise_angle(dir, sun_dir);
    float half_angular = angular_diameter / 2.0;
    float dir_elevation = M_PI_2_F - direction.x;

    /* if ray inside sun disc render it, otherwise render sky */
    if (sun_dir_angle < half_angular && sun_disc == 1) {
      /* get 2 pixels data */
      float3 pixel_bottom = float3(nishita_data[0], nishita_data[1], nishita_data[2]);
      float3 pixel_top = float3(nishita_data[3], nishita_data[4], nishita_data[5]);
      float y;

      /* sun interpolation */
      if (sun_elevation - half_angular > 0.0) {
        if ((sun_elevation + half_angular) > 0.0) {
          y = ((dir_elevation - sun_elevation) / angular_diameter) + 0.5;
          xyz = mix(pixel_bottom, pixel_top, y) * sun_intensity;
        }
      }
      else {
        if (sun_elevation + half_angular > 0.0) {
          y = dir_elevation / (sun_elevation + half_angular);
          xyz = mix(pixel_bottom, pixel_top, y) * sun_intensity;
        }
      }
      /* limb darkening, coefficient is 0.6f */
      float angle_fraction = sun_dir_angle / half_angular;
      float limb_darkening = (1.0 - 0.6 * (1.0 - sqrt(1.0 - angle_fraction * angle_fraction)));
      xyz *= limb_darkening;
    }
    /* sky */
    else {
      /* sky interpolation */
      float x = (direction.y + M_PI_F + sun_rotation) / (2 * M_PI_F);
      /* more pixels toward horizon compensation */
      float y = sqrt(dir_elevation / M_PI_2_F);
      if (x > 1.0) {
        x = x - 1.0;
      }
      constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
      xyz = texture.sample(linearSampler, float2(x, y)).xyz;
    }
  }
  /* ground */
  else {
    if (dir.z < -0.4) {
      xyz = float3(0, 0, 0);
    }
    else {
      /* black ground fade */
      float mul = pow(1.0 + dir.z * 2.5, 3.0);
      /* interpolation */
      float x = (direction.y + M_PI_F + sun_rotation) / (2 * M_PI_F);
      float y = 1e-3; /// @todo this seems fishy
      if (x > 1.0) {
        x = x - 1.0;
      }
      constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
      xyz = texture.sample(linearSampler, float2(x, y)).xyz * mul;
    }
  }
  /* convert to RGB */
  return xyz_to_rgb(xyz);
}

template<
    int TextureIndex
>
struct TexNishita {
    float scale;
    
    float3 vector;
    float4 color;
    float data[10];
    
    void compute(device Context &ctx, ShadingContext shading) {
        color = float4(scale * sky_radiance_nishita(shading.wo * float3(1, -1, -1), data, ctx.textures[TextureIndex]), 1);
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
    
    void compute(device Context &ctx, ShadingContext shading) {
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
    
    void compute(device Context &ctx, ShadingContext shading) {
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

/**
 * @todo not supported
 */
struct NormalProduct {
    float3 normal;
    float dot;
    
    void compute(device Context &ctx, ShadingContext shading) {
        dot = 1;
    }
};

struct kNormalMap {
    enum Space {
        SPACE_TANGENT,
        SPACE_WORLD
    };
};

template<
    kNormalMap::Space Space
>
struct NormalMap {
    float4 color;
    float strength;
    
    float3 normal;
    
    void compute(device Context &ctx, ShadingContext shading) {
        float s = max(strength, 0.f);
        
        normal = normalize(2 * color.xyz - 1);
        normal = s * normal + (1 - s) * float3(0, 0, 1);
        normal = normalize(normal);
        
        float3x3 onb;
        onb[0] = shading.tu;
        onb[1] = shading.tv;
        onb[2] = shading.normal;
        
        switch (Space) {
        case kNormalMap::SPACE_TANGENT:
            normal = onb * normal;
            break;
        case kNormalMap::SPACE_WORLD:
            /// @todo verify
            break;
        }
    }
};

struct Displacement {
    float height;
    float midlevel;
    float3 normal;
    float scale;
    
    float3 displacement;
    
    void compute(device Context &ctx, ShadingContext shading) {
        displacement = float3(0);
    }
};

struct Fresnel {
    float ior;
    float3 normal;
    
    float fac;
    
    void compute(device Context &ctx, ShadingContext shading) {
        float cosI = dot(shading.wo, normal);
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
        OPERATION_MULTIPLY_ADD,
        OPERATION_POWER,
        OPERATION_MINIMUM,
        OPERATION_MAXIMUM,
        OPERATION_TANGENT,
        OPERATION_LESS_THAN,
        OPERATION_GREATER_THAN,
        OPERATION_MODULO
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        switch (Operation) {
        case kMath::OPERATION_ADD:
            value = value + value_001; break;
        case kMath::OPERATION_SUBTRACT:
            value = value - value_001; break;
        case kMath::OPERATION_MULTIPLY:
            value = value * value_001; break;
        case kMath::OPERATION_DIVIDE:
            value = safe_divide(value, value_001, 0); break;
        case kMath::OPERATION_MULTIPLY_ADD:
            value = value * value_001 + value_002; break;
        case kMath::OPERATION_POWER:
            /// @todo verify
            value = pow(value, value_001); break;
        case kMath::OPERATION_MINIMUM:
            /// @todo verify
            value = min(value, value_001); break;
        case kMath::OPERATION_MAXIMUM:
            /// @todo verify
            value = max(value, value_001); break;
        case kMath::OPERATION_TANGENT:
            /// @todo verify
            value = tan(value); break;
        case kMath::OPERATION_LESS_THAN:
            /// @todo verify
            value = value < value_001; break;
        case kMath::OPERATION_GREATER_THAN:
            /// @todo verify
            value = value > value_001; break;
        case kMath::OPERATION_MODULO:
            /// @todo verify
            value = fmod(value, value_001); break;
        }
        
        if (Clamp) {
            value = saturate(value);
        }
    }
};

struct kSeparateColor {
    enum Mode {
        MODE_RGB,
        MODE_HSV
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        switch (Mode) {
        case kSeparateColor::MODE_RGB: {
            red = color.x;
            green = color.y;
            blue = color.z;
            break;
        }
        
        case kSeparateColor::MODE_HSV: {
            /// @todo verify
            float3 hsv = rgb2hsv(color.xyz);
            red = hsv.x;
            green = hsv.y;
            blue = hsv.z;
            break;
        }
        }
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        color = float4(red, green, blue, 1);
    }
};

struct HueSaturation {
    float4 color;
    float fac;
    float hue;
    float saturation;
    float value;
    
    void compute(device Context &ctx, ShadingContext shading) {
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        float a = 1 + contrast;
        float b = bright - contrast / 2;
        
        color = max(a * color + b, 0.f);
    }
};

struct Gamma {
    float4 color;
    float gamma;
    
    void compute(device Context &ctx, ShadingContext shading) {
        if (gamma == 0)
            color.xyz = 1;
        else
            color.xyz = select(color.xyz, pow(color.xyz, gamma), color.xyz > 0);
    }
};

struct kColorMix {
    enum BlendType {
        BLEND_TYPE_MIX,
        BLEND_TYPE_ADD,
        BLEND_TYPE_MULTIPLY,
        BLEND_TYPE_SCREEN,
        BLEND_TYPE_OVERLAY,
        BLEND_TYPE_SUB,
        BLEND_TYPE_COLOR,
        BLEND_TYPE_LIGHTEN,
        BLEND_TYPE_DARKEN,
        BLEND_TYPE_VALUE
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
    
    void compute(device Context &ctx, ShadingContext shading) {
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
        case kColorMix::BLEND_TYPE_OVERLAY: {
            color = color1;
            
            for (int dim = 0; dim < 3; dim++) {
                if (color[dim] < 0.5)
                    color[dim] *= 1 - fac + 2 * fac * color2[dim];
                else
                    color[dim] = 1 - (1 - fac + 2 * fac * (1 - color2[dim])) * (1 - color[dim]);
            }
            
            break;
        }
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
        case kColorMix::BLEND_TYPE_VALUE: {
            /// @todo verify
            float3 hsv = rgb2hsv(color1.xyz);
            hsv.z = rgb2hsv(color2.xyz).z;
            color = lerp(color1, float4(hsv2rgb(hsv), color2.w), fac);
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
    
    void compute(device Context &ctx, ShadingContext shading) {
        color.xyz = color.xyz - fac * (2 * color.xyz - 1);
    }
};

struct Emission {
    float4 color;
    float strength;
    float weight;
    
    UberShader emission;
    
    void compute(device Context &ctx, ShadingContext shading) {
        emission.lobeProbabilities[0] = 1;
        emission.emission = color.xyz * strength;
    }
};

struct Background {
    float4 color;
    float strength;
    float weight;
    
    UberShader background;
    
    void compute(device Context &ctx, ShadingContext shading) {
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
    
    void compute(device Context &ctx, ShadingContext shading) {
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
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
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
 * @todo not tested, should probably not use Fresnel term
 */
template<
    kBsdfGlossy::Distribution Distribution
>
struct BsdfGlossy {
    float4 color;
    float3 normal;
    float roughness;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
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
        SUBSURFACE_METHOD_RANDOM_WALK,
        SUBSURFACE_METHOD_RANDOM_WALK_FIXED_RADIUS
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
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
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
        bsdf.emission = alpha * emission.xyz * emissionStrength;
    }
};

struct LayerWeight {
    float blend;
    float3 normal;
    
    float fresnel;
    float facing;
    
    void compute(device Context &ctx, ShadingContext shading) {
        const bool backfacing = dot(shading.wo, normal) < 0;
        
        const float cosI = dot(shading.wo, normal);
        float eta = max(1 - blend, 1e-5);
        eta = backfacing ? eta : 1 / eta;
        
        fresnel = fresnelDielectricCos(cosI, eta);
        facing = abs(cosI);
        
        if (blend != 0.5) {
            float b = clamp(blend, float(0), float(1 - 1e-5));
            b = (b < 0.5) ? 2 * b : 0.5 / (1 - b);
            facing = pow(facing, b);
        }
        
        facing = 1 - facing;
    }
};

struct Value {
    float value;
    void compute(device Context &ctx, ShadingContext shading) {}
};

struct RGB {
    float4 color;
    void compute(device Context &ctx, ShadingContext shading) {}
};

struct RGBToBW {
    float4 color;
    float val;
    
    void compute(device Context &ctx, ShadingContext shading) {
        /// @todo verify
        val = luminance(color.xyz);
    }
};

struct Attribute {
    float3 vector;
    float4 color;
    
    void compute(device Context &ctx, ShadingContext shading) {
        vector = shading.generated;
        color = 1; /// @todo
    }
};

struct BsdfAnisotropic {
    float anisotropy;
    float4 color;
    float3 normal;
    float rotation;
    float3 tangent;
    float roughness;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
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

struct BsdfRefraction {
    float4 color;
    float ior;
    float3 normal;
    float roughness;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        const float r2 = square(max(roughness, 1e-4));
        bsdf.transmission = (Transmission){
            .reflectionAlpha = r2,
            .transmissionAlpha = r2,
            .baseColor = color.xyz,
            .Cspec0 = 0,
            .ior = ior,
            .weight = 1,
            .onlyRefract = true
        };
        bsdf.lobeProbabilities[2] = 1;
        bsdf.normal = normal;
    }
};

struct BsdfTransparent {
    float4 color;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        bsdf.alpha = 0;
        bsdf.alphaWeight = color.xyz;
    }
};

struct BsdfDiffuse {
    float4 color;
    float3 normal;
    float roughness;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = color.xyz,
            .sheenWeight = 0,
            .roughness = roughness
        };
        
        bsdf.normal = normal;
        bsdf.lobeProbabilities[0] = 1;
    }
};

struct BsdfVelvet {
    float4 color;
    float3 normal;
    float sigma;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = color.xyz,
            .sheenWeight = 0,
            .roughness = sigma
        };
        
        bsdf.normal = normal;
        bsdf.lobeProbabilities[0] = 1;
    }
};

struct BsdfHair {
    float4 color;
    float offset;
    float roughnessu;
    float roughnessv;
    float3 tangent;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = color.xyz,
            .sheenWeight = 0,
            .roughness = 0
        };
        
        bsdf.normal = tangent;
        bsdf.lobeProbabilities[0] = 1;
    }
};

struct BsdfTranslucent {
    float4 color;
    float3 normal;
    float weight;
    
    UberShader bsdf;
    
    void compute(device Context &ctx, ShadingContext shading) {
        bsdf.diffuse = (Diffuse){
            .diffuseWeight = color.xyz,
            .sheenWeight = 0,
            .roughness = 1,
            .translucent = true
        };
        
        bsdf.normal = normal;
        bsdf.lobeProbabilities[0] = 1;
    }
};

/**
 * @todo would be cool if some materials (or lobes thereof) would be mixed analytically instead of stochastically
 * @todo not working yet
 */
struct AddShader {
    UberShader shader;
    UberShader shader_001;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        if (shading.rnd.x < 0.5f) {
            shading.rnd.x /= 0.5f;
            shader = shader_001;
        } else {
            shading.rnd.x = 2 * (shading.rnd.x - 0.5f);
        }
        
        shader.weight *= 2;
    }
};

/**
 * @todo would be cool if some materials (or lobes thereof) would be mixed analytically instead of stochastically
 */
struct MixShader {
    float fac;
    UberShader shader;
    UberShader shader_001;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        if (shading.rnd.x < fac) {
            shading.rnd.x /= fac;
            shader = shader_001;
        } else {
            shading.rnd.x = (shading.rnd.x - fac) / (1 - fac);
        }
    }
};

struct kMix {
    enum FactorMode {
        FACTOR_MODE_UNIFORM,
        FACTOR_MODE_NON_UNIFORM
    };
};

template<
    bool ClampFactor,
    bool ClampResult,
    kMix::FactorMode FactorMode
>
struct Mix {
    float4 a_Color, b_Color, result_Color;
    float a_Float, b_Float, result_Float;
    float3 a_Vector, b_Vector, result_Vector;
    
    float factor_Float;
    float3 factor_Vector;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        /// @todo verify
        
        if (ClampFactor) {
            factor_Float = saturate(factor_Float);
            factor_Vector = saturate(factor_Vector);
        }
        
        if (FactorMode == kMix::FACTOR_MODE_UNIFORM) {
            result_Vector = lerp(a_Vector, b_Vector, factor_Float);
        } else {
            result_Vector = a_Vector + (b_Vector - a_Vector) * factor_Vector;
        }
        
        result_Float = lerp(a_Float, b_Float, factor_Float);
        result_Color = lerp(a_Color, b_Color, factor_Float);
        
        if (ClampResult) {
            result_Color = saturate(result_Color);
        }
    }
};

struct OutputMaterial {
    float3 displacement;
    float thickness;
    
    UberShader surface;
    UberShader volume;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        shading.material = surface;
    }
};

struct OutputWorld {
    float thickness;
    UberShader surface;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        shading.material = surface;
    }
};

struct OutputLight {
    UberShader surface;
    
    void compute(device Context &ctx, thread ShadingContext &shading) {
        thread UberShader &mat = shading.material;
        mat.alpha = 0;
        mat.emission = surface.emission;
    }
};

float3 VECTOR(float v)  { return float3(v); } /// @todo verify
float3 VECTOR(float2 v) { return float3(v, 0); }
float3 VECTOR(float3 v) { return v; }
float3 VECTOR(float4 v) { return v.xyz; }
float3 VECTOR(UberShader v) { return float3(0); } /// @todo verify ???

float4 RGBA(float v) { return float4(v, v, v, 1); }
float4 RGBA(float2 v) { return float4(v, 0, 1); }
float4 RGBA(float3 v) { return float4(v, 1); }
float4 RGBA(float4 v) { return v; }
float4 RGBA(UberShader v) { return float4(v.emission, 1); } /// @todo verify ???

float VALUE(float v) { return v; }
float VALUE(float3 v) { return (v.x + v.y + v.z) / 3; }
float VALUE(float4 v) { return v.w * (v.x + v.y + v.z) / 3; }

UberShader SHADER(UberShader v) { return v; }
UberShader SHADER(float3 v) {
    UberShader m;
    m.emission = v;
    return m;
}
UberShader SHADER(float v) { return SHADER(float3(v)); }
UberShader SHADER(float2 v) { return SHADER(float3(v, 0)); }
UberShader SHADER(float4 v) { return SHADER(v.xyz); }
