#pragma once

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
