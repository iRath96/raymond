#pragma once

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

