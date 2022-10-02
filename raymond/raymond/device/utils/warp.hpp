#pragma once

namespace warp {

float2 equirectSphereToSquare(float3 vector) {
    return float2(
        (atan2(vector.x, vector.y) - M_PI_F) / (2 * M_PI_F),
        acos(vector.z / length(vector)) / M_PI_F
    );
}

float3 uniformSquareToSphere(float2 uv) {
    float z = 1 - 2 * uv.y;
    float r = safe_sqrt(1 - z * z);
    
    float cos;
    float sin = sincos(2 * M_PI_F * uv.x, cos);
    
    return float3(r * cos, r * sin, z);
}

float2 uniformSphereToSquare(float3 vector) {
    float y = (1 - vector.z) / 2;
    float x = atan2(vector.y, vector.x) / (2 * M_PI_F);
    return float2(select(x, x + 1, x < 0), y);
}

float uniformSquareToSpherePdf() {
    return 1 / (4 * M_PI_F);
}

/// @todo not a nice mapping
float2 uniformSquareToDisk(float2 uv) {
    float cos;
    float sin = sincos(2 * M_PI_F * uv.x, cos);
    float r = sqrt(uv.y);
    
    return float2(r * cos, r * sin);
}

/**
 * Samples vectors in the upper hemisphere weighted by their cosine value.
 * @note The PDF of this is given by:
 *   @code max(0, cosTheta(w)) / pi @endcode
 */
float3 uniformSquareToCosineWeightedHemisphere(float2 rnd) {
    float cosTheta = sqrt(rnd.x);
    float sinTheta = sqrt(1 - square(cosTheta));
    
    float cosPhi;
    float sinPhi = sincos(2 * M_PI_F * rnd.y, cosPhi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

float2 uniformSquareToTriangleBarycentric(float2 rnd) {
    float x = sqrt(rnd.x);
    return float2(1 - x, x * rnd.y);
}

}
