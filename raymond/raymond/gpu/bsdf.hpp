#pragma once

#include "ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

float3x3 buildOrthonormalBasis(float3 n) {
    float3x3 frame;
    frame[0] = (abs(n.y) < 0.9999f) ?
        normalize(cross(n, float3(0, 1, 0))) :
        float3(1, 0, 0);
    frame[1] = cross(frame[0], n);
    frame[2] = n;
    return frame;
}

float safe_sqrtf(float f) { return sqrt(max(f, 0.0f)); }
float sqr(float f) { return f * f; }

/**
 * Taken from blender.
 * For more information and an explaination of the algorithm, see https://github.com/blender/blender/blob/594f47ecd2d5367ca936cf6fc6ec8168c2b360d0/intern/cycles/kernel/kernel_montecarlo.h#L196
 */
float3 ensure_valid_reflection(float3 Ng, float3 I, float3 N)
{
  float3 R = 2 * dot(N, I) * N - I;

  float threshold = min(0.9f * dot(Ng, I), 0.01f);
  if (dot(Ng, R) >= threshold) {
    return N;
  }

  float NdotNg = dot(N, Ng);
  float3 X = normalize(N - NdotNg * Ng);

  float Ix = dot(I, X), Iz = dot(I, Ng);
  float Ix2 = sqr(Ix), Iz2 = sqr(Iz);
  float a = Ix2 + Iz2;

  float b = safe_sqrtf(Ix2 * (a - sqr(threshold)));
  float c = Iz * threshold + a;

  float fac = 0.5f / a;
  float N1_z2 = fac * (b + c), N2_z2 = fac * (-b + c);
  bool valid1 = (N1_z2 > 1e-5f) && (N1_z2 <= (1.0f + 1e-5f));
  bool valid2 = (N2_z2 > 1e-5f) && (N2_z2 <= (1.0f + 1e-5f));

  float2 N_new;
  if (valid1 && valid2) {
    float2 N1 = float2(safe_sqrtf(1.0f - N1_z2), safe_sqrtf(N1_z2));
    float2 N2 = float2(safe_sqrtf(1.0f - N2_z2), safe_sqrtf(N2_z2));

    float R1 = 2 * (N1.x * Ix + N1.y * Iz) * N1.y - Iz;
    float R2 = 2 * (N2.x * Ix + N2.y * Iz) * N2.y - Iz;

    valid1 = (R1 >= 1e-5f);
    valid2 = (R2 >= 1e-5f);
    if (valid1 && valid2) {
      N_new = (R1 < R2) ? N1 : N2;
    } else {
      N_new = (R1 > R2) ? N1 : N2;
    }
  } else if (valid1 || valid2) {
    float Nz2 = valid1 ? N1_z2 : N2_z2;
    N_new = float2(safe_sqrtf(1.0f - Nz2), safe_sqrtf(Nz2));
  } else {
    return Ng;
  }

  return N_new.x * X + N_new.y * Ng;
}

/**
 * Square root function that returns zero for negative arguments.
 * This is useful to prevent NaNs in the presence of numerical instabilities.
 */
float safe_sqrt(float v) { return v <= 0 ? 0 : sqrt(v); }

/**
 * Linear interpolation function.
 * Interpolates between @c a at @c v=0 and @c b at @c v=1 .
 */
template<typename T>
T lerp(T a, T b, float v) { return (1 - v) * a + v * b; }

/**
 * Square function. It does exactly what you would guess.
 */
template<typename T>
T square(T v) { return v * v; }

/**
 * Arithmetic mean of a @c float3 vector.
 */
float mean(float3 v) { return (v.x + v.y + v.z) / 3; }

struct ShadingFrame {
    static bool sameHemisphere(float3 wi, float3 wo) {
        return cosTheta(wi) * cosTheta(wo) > 0;
    }

    static float cosTheta(float3 w) { return w.z; }
    static float cosTheta2(float3 w) { return square(w.z); }
    static float absCosTheta(float3 w) {  return abs(w.z); }
    
    static float sinTheta(float3 w) { return safe_sqrt(1 - cosTheta2(w)); }
    static float sinTheta2(float3 w) { return 1 - cosTheta2(w); }
    
    static float cosPhiSinTheta(float3 w) { return w.x; }
    static float sinPhiSinTheta(float3 w) { return w.y; }

    static float tanTheta(float3 w) {
        const float cos = cosTheta(w);
        return safe_sqrt(1 - square(cos)) / cos;
    }
    
    static float tanTheta2(float3 w) {
        const float cos2 = cosTheta2(w);
        return (1 - cos2) / cos2;
    }
};

struct BSDFSample {
    float pdf;
    float3 wi;
    float3 weight;
    Ray::Flags flags;
    
    static BSDFSample invalid() {
        BSDFSample result;
        result.pdf = 0;
        result.weight = 0;
        result.flags = Ray::TYPE_INVALID;
        return result;
    }
};

//
// MARK: BSDF utility functions
//

float schlickWeight(float cosTheta) {
    float m = saturate(1 - cosTheta);
    return (m * m) * (m * m) * m;
}

/**
 * The Schlick approximation of the Fresnel term.
 * @note See "An Inexpensive BRDF Model for Physically-based Rendering" [Schlick 1994].
 */
template<typename T>
T schlick(T F0, float cosTheta) {
    return F0 + (1 - F0) * schlickWeight(cosTheta);
}

/**
 * Unpolarized Fresnel term for dielectric materials.
 * @param cosThetaT Returns the cosine of the transmitted ray, or -1 in the case of total internal reflection.
 * @param eta The relative IOR (n1 / n2).
 */
float fresnelDielectric(float3 i, float3 n, thread float &cosThetaT, float eta) {
    float cosThetaTSqr = 1 - eta * eta * (1 - square(dot(n, i)));
    
    if (cosThetaTSqr <= 0.0f) {
        // total internal reflection
        cosThetaT = -1;
        return 1;
    }

    float cosThetaI = abs(dot(n, i));
    cosThetaT = sqrt(cosThetaTSqr);

    float Rs = (cosThetaI - eta * cosThetaT)
             / (cosThetaI + eta * cosThetaT);
    float Rp = (eta * cosThetaI - cosThetaT)
             / (eta * cosThetaI + cosThetaT);

    /// Average the power of both polarizations
    return 0.5f * (Rs * Rs + Rp * Rp);
}

/**
 * Samples vectors in the upper hemisphere weighted by their cosine value.
 * @note The PDF of this is given by:
 *   @code max(0, cosTheta(w)) / pi @endcode
 */
float3 sampleCosineWeightedHemisphere(float2 rnd) {
    float cosTheta = sqrt(rnd.x);
    float sinTheta = sqrt(1 - (cosTheta * cosTheta));
    float phi = 2 * M_PI_F * rnd.y;
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

/**
 * Evaluates the isotropic GTR1 normal distribution function.
 * @see "Diffuse Reflection of Light from a Matt Surface" [Berry 1923]
 * @see "Physically Based Shading at Disney" [Burley 2012]
 */
float gtr1(float3 wh, float a) {
    float nDotH = ShadingFrame::cosTheta(wh);
    float a2 = square(a);
    float t = 1 + (a2 - 1) * square(nDotH);
    return (a2 - 1) / (M_PI_F * log(a2) * t);
}

/**
 * Samples the isotropic GTR1 normal distribution function.
 * @return A microfacet normal that will always lie in the upper hemisphere.
 * @note The PDF of @c wh is given by:
 *   @code cosTheta(wh) * D(wh) @endcode
 */
float3 sampleGTR1(float2 rnd, float a) {
    float a2 = square(a);

    float cosTheta = safe_sqrt((1 - pow(a2, 1 - rnd.x)) / (1 - a2));
    float sinTheta = safe_sqrt(1 - (cosTheta * cosTheta));
    float phi = 2 * M_PI_F * rnd.y;
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

/**
 * Isotropic Smith shadowing/masking function for the GGX microfacet distribution.
 * This function also ensures that the orientation of @c w matches the orientation of @c wh and returns @c 0 if that is not the case.
 * @note This is used for the clearcoat lobe, even though it is not a physically correct match for its GTR1 NDF.
 *       While better matches became available after the original Disney BRDF publication, they seemingly liked the look of this function more.
 */
float smithG1(float3 w, float3 wh, float a) {
    /// Ensure correct orientation by projecting both @c w and @c wh into the upper hemisphere and checking that the angle they form is less than 90°
    if (dot(w, wh) * ShadingFrame::cosTheta(w) * ShadingFrame::cosTheta(wh) <= 0) return 0;
    
    /// Special case: if @c cosTheta of @c w is large, we know that the tangens will be @c 0 and hence our result is @c 1
    if (abs(ShadingFrame::cosTheta(w)) >= 1) return 1;
    
    const float a2tanTheta2 = square(a) * ShadingFrame::tanTheta2(w);
    return 2 / (1 + sqrt(1 + a2tanTheta2));
}

/**
 * Anisotropic Smith shadowing/masking function for the GGX microfacet distribution.
 * This function also ensures that the orientation of @c w matches the orientation of @c wh and returns @c 0 if that is not the case.
 * @note This is used for the specular lobes of the Disney BSDF.
 */
float anisotropicSmithG1(float3 w, float3 wh, float ax, float ay) {
    /// Ensure correct orientation by projecting both @c w and @c wh into the upper hemisphere and checking that the angle they form is less than 90°
    if (dot(w, wh) * ShadingFrame::cosTheta(w) * ShadingFrame::cosTheta(wh) <= 0) return 0;
    
    /// Special case: if @c cosTheta of @c w is large, we know that the tangent will be @c 0 and hence our result is @c 1
    if (abs(ShadingFrame::cosTheta(w)) >= 1) return 1;
    
    const float a2tanTheta2 = (
        square(ax * ShadingFrame::cosPhiSinTheta(w)) +
        square(ay * ShadingFrame::sinPhiSinTheta(w))
    ) / ShadingFrame::cosTheta2(w);
    return 2 / (1 + sqrt(1 + a2tanTheta2));
}

/**
 * Evaluates the anisotropic GGX normal distribution function.
 * @see "Microfacet Models for Refraction through Rough Surfaces" [Walter et al. 2007]
 */
float anisotropicGGX(float3 wh, float ax, float ay) {
    float nDotH = ShadingFrame::cosTheta(wh);
    float a = ShadingFrame::cosPhiSinTheta(wh) / ax;
    float b = ShadingFrame::sinPhiSinTheta(wh) / ay;
    float c = square(a) + square(b) + square(nDotH);
    return 1 / (M_PI_F * ax * ay * square(c));
}

/**
 * Sampling of the visible normal distribution function (VNDF) of the GGX microfacet distribution with Smith shadowing function by [Heitz 2018].
 * @note The PDF of @c wh is given by:
 *   @code G1(wo) * max(0, dot(wo, wh)) * D(wh) / cosTheta(wo) @endcode
 * @see For details on how and why this works, check out Eric Heitz' great JCGT paper "Sampling the GGX Distribution of Visible Normals".
 */
float3 sampleGGXVNDF(float2 rnd, float ax, float ay, float3 wo) {
    // Addition: flip sign of incident vector for transmission
    float sgn = sign(ShadingFrame::cosTheta(wo));
	// Section 3.2: transforming the view direction to the hemisphere configuration
	float3 Vh = sgn * normalize(float3(ax * wo.x, ay * wo.y, wo.z));
	// Section 4.1: orthonormal basis (with special case if cross product is zero)
	float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
	float3 T1 = lensq > 0 ? float3(-Vh.y, Vh.x, 0) * rsqrt(lensq) : float3(1,0,0);
	float3 T2 = cross(Vh, T1);
	// Section 4.2: parameterization of the projected area
	float r = sqrt(rnd.x);
	float phi = 2.0 * M_PI_F * rnd.y;
	float t1 = r * cos(phi);
	float t2 = r * sin(phi);
	float s = 0.5 * (1.0 + Vh.z);
	t2 = (1.0 - s)*sqrt(1.0 - t1*t1) + s*t2;
	// Section 4.3: reprojection onto hemisphere
	float3 Nh = t1*T1 + t2*T2 + sqrt(max(0.0, 1.0 - t1*t1 - t2*t2))*Vh;
	// Section 3.4: transforming the normal back to the ellipsoid configuration
	float3 Ne = normalize(float3(ax * Nh.x, ay * Nh.y, max(0.f, Nh.z)));
	return sgn * Ne;
}

float fresnelDielectricCos(float cosi, float eta) {
    float c = abs(cosi);
    float g = eta * eta - 1 + c * c;
    if (g > 0) {
        g = sqrt(g);
        float A = (g - c) / (g + c);
        float B = (c * (g + c) - 1) / (c * (g - c) + 1);
        return 0.5f * A * A * (1 + B * B);
    }
    return 1.0f;
}

float3 interpolateFresnel(float3 wi, float3 wh, float ior, float F0, float3 cspec0) {
  float F0_norm = 1 / (1 - F0);
  float FH = (fresnelDielectricCos(dot(wi, wh), ior) - F0) * F0_norm;
  return cspec0 * (1 - FH) + float3(1) * FH;
}

float3 fresnelReflectionColor(float3 wi, float3 wh, float ior, float3 Cspec0) {
    float F0 = fresnelDielectricCos(1, ior);
    return interpolateFresnel(wi, wh, ior, F0, Cspec0);
}

/**
 * Matches Cycles fairly well.
 */
struct Diffuse {
    float3 diffuseWeight = 0;
    float3 sheenWeight = 0;
    float roughness;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        return float3(0); /// @todo
    }
    
    BSDFSample sample(float2 rnd, float3 wo) {
        BSDFSample result;
        result.wi = sampleCosineWeightedHemisphere(rnd);
        if (!ShadingFrame::sameHemisphere(result.wi, wo)) {
            result.wi *= -1;
        }
        
        const float NdotL = abs(ShadingFrame::cosTheta(result.wi));
        result.pdf = M_1_PI_F * NdotL;
        
        if (!(result.pdf > 0))
            return BSDFSample::invalid();
        
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
        return result;
    }
};

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
    
    BSDFSample sample(float2 rnd, float3 wo) {
        BSDFSample result;
        
        const float3 wh = sampleGGXVNDF(rnd, alphaX, alphaY, wo);
        result.pdf = anisotropicGGX(wh, alphaX, alphaY) *
            anisotropicSmithG1(wo, wh, alphaX, alphaY) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        
        if (!(result.pdf > 0))
            return BSDFSample::invalid();
        
        result.wi = reflect(-wo, wh);
        if (!ShadingFrame::sameHemisphere(result.wi, wo))
            return BSDFSample::invalid();
        
        result.pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(result.wi, wh, ior, Cspec0);
        const float Gi = anisotropicSmithG1(result.wi, wh, alphaX, alphaY);
        result.weight = weight * F * Gi;
        return result;
    }
};

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
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        return float3(0); /// @todo
    }
    
    BSDFSample sample(float2 rnd, float3 wo) {
        BSDFSample result;
        
        float eta = ShadingFrame::cosTheta(wo) > 0 ? ior : 1 / ior;
        if (eta == 1) eta = 1.01; /// @todo this is a hack to avoid singularities
        
        const float Fr = fresnelDielectricCos(ShadingFrame::cosTheta(wo), eta);
        if (rnd.x < Fr) {
            // reflect
            rnd.x /= Fr;
            
            const float alphaX = reflectionAlpha;
            const float alphaY = reflectionAlpha;
            
            const float3 wh = sampleGGXVNDF(rnd, alphaX, alphaY, wo);
            result.pdf = anisotropicGGX(wh, alphaX, alphaY) *
                anisotropicSmithG1(wo, wh, alphaX, alphaY) *
                abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
            
            if (!(result.pdf > 0))
                return BSDFSample::invalid();
            
            result.wi = reflect(-wo, wh);
            if (!ShadingFrame::sameHemisphere(result.wi, wo))
                return BSDFSample::invalid();
            
            result.pdf *= Fr;
            result.pdf *= 1 / abs(4 * dot(wo, wh));
            
            const float3 F = fresnelReflectionColor(result.wi, wh, eta, Cspec0);
            const float Gi = anisotropicSmithG1(result.wi, wh, alphaX, alphaY);
            result.weight = weight * F * Gi;
            return result;
        } else {
            // refract
            rnd.x = (rnd.x - Fr) / (1 - Fr);
            
            const float alphaX = transmissionAlpha;
            const float alphaY = transmissionAlpha;
            
            const float3 wh = sampleGGXVNDF(rnd, alphaX, alphaY, wo);
            result.pdf = anisotropicGGX(wh, alphaX, alphaY) *
                anisotropicSmithG1(wo, wh, alphaX, alphaY) *
                abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
            
            if (!(result.pdf > 0))
                return BSDFSample::invalid();
            
            //result.wi = (dot(wh, wo) / eta - cosThetaT) * wh - wo / eta;
            result.wi = refract(-wo, wh, 1/eta);
            if (ShadingFrame::sameHemisphere(result.wi, wo))
                return BSDFSample::invalid();
            
            result.pdf *= 1 - Fr;
            result.pdf *= abs(dot(result.wi, wh) / square(dot(result.wi, wh) + dot(wh, wo) / eta));
            
            //const float3 F = fresnelReflectionColor(result.wi, wh, eta, Cspec0);
            const float Gi = anisotropicSmithG1(result.wi, wh, alphaX, alphaY);
            result.weight = weight * baseColor * Gi;
            return result;
        }
    }
};

/**
 * Not perfect yet: failure case for clearcoatRoughness=0.3.
 */
struct Clearcoat {
    float alpha;
    float weight = 0;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        return float3(0); /// @todo
    }
    
    BSDFSample sample(float2 rnd, float3 wo) {
        BSDFSample result;
        
        const float3 wh = sampleGGXVNDF(rnd, alpha, alpha, wo);
        result.pdf = anisotropicGGX(wh, alpha, alpha) *
            anisotropicSmithG1(wo, wh, alpha, alpha) *
            abs(dot(wo, wh) / ShadingFrame::cosTheta(wo));
        
        if (!(result.pdf > 0))
            return BSDFSample::invalid();
        
        result.wi = reflect(-wo, wh);
        if (!ShadingFrame::sameHemisphere(result.wi, wo))
            return BSDFSample::invalid();
        
        result.pdf *= 1 / abs(4 * dot(wo, wh));
        
        const float3 F = fresnelReflectionColor(result.wi, wh, 1.5, float3(0.04));
        const float Gi = smithG1(result.wi, wh, alpha);
        result.weight = 0.25 * weight * F * Gi;
        return result;
    }
};

// adapted from blender/intern/cycles/util/color.h
float3 rgb2hsv(float3 rgb) {
  float cmax, cmin, h, s, v, cdelta;
  float3 c;

  cmax = max(rgb.x, max(rgb.y, rgb.z));
  cmin = min(rgb.x, min(rgb.y, rgb.z));
  cdelta = cmax - cmin;

  v = cmax;

  if (cmax != 0.0f) {
    s = cdelta / cmax;
  } else {
    s = 0.0f;
    h = 0.0f;
  }

  if (s != 0.0f) {
    c = (cmax - rgb) / cdelta;

    if (rgb.x == cmax)
      h = c.z - c.y;
    else if (rgb.y == cmax)
      h = 2.0f + c.x - c.z;
    else
      h = 4.0f + c.y - c.x;

    h /= 6.0f;

    if (h < 0.0f)
      h += 1.0f;
  } else {
    h = 0.0f;
  }

  return float3(h, s, v);
}

// adapted from blender/intern/cycles/util/color.h
float3 hsv2rgb(float3 hsv) {
  float i, f, p, q, t, h, s, v;
  float3 rgb;

  h = hsv.x;
  s = hsv.y;
  v = hsv.z;

  if (s != 0.0f) {
    if (h == 1.0f)
      h = 0.0f;

    h *= 6.0f;
    i = floor(h);
    f = h - i;
    rgb = f;
    p = v * (1.0f - s);
    q = v * (1.0f - (s * f));
    t = v * (1.0f - (s * (1.0f - f)));

    if (i == 0.0f)
      rgb = float3(v, t, p);
    else if (i == 1.0f)
      rgb = float3(q, v, p);
    else if (i == 2.0f)
      rgb = float3(p, v, t);
    else if (i == 3.0f)
      rgb = float3(p, q, v);
    else if (i == 4.0f)
      rgb = float3(t, p, v);
    else
      rgb = float3(v, p, q);
  } else {
    rgb = float3(v, v, v);
  }

  return rgb;
}

// adapted from blender/intern/cycles/kernel/osl/cycles_osl_shaders/node_mapping.osl
float3x3 euler2mat(float3 euler) {
    float cx, cy, cz;
    float sx = sincos(euler.x, cx);
    float sy = sincos(euler.y, cy);
    float sz = sincos(euler.z, cz);
    
    float3x3 mat;
    
    mat[0][0] = cy * cz;
    mat[0][1] = cy * sz;
    mat[0][2] = -sy;

    mat[1][0] = sy * sx * cz - cx * sz;
    mat[1][1] = sy * sx * sz + cx * cz;
    mat[1][2] = cy * sx;

    mat[2][0] = sy * cx * cz + sx * sz;
    mat[2][1] = sy * cx * sz - sx * cz;
    mat[2][2] = cy * cx;
    
    return mat;
}

