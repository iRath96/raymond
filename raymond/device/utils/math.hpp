#pragma once

/// "Building an Orthonormal Basis, Revisited"
float3x3 buildOrthonormalBasis(float3 n) {
  const float sign = copysign(1.0f, n.z);
  const float a = -1.0f / (sign + n.z);
  const float b = n.x * n.y * a;
  
  float3x3 frame;
  frame[0] = float3(1.0f + sign * n.x * n.x * a, sign * b, -sign * n.x);
  frame[1] = float3(b, sign + n.y * n.y * a, -n.y);
  frame[2] = n;
  return frame;
}

float safe_sqrtf(float f) { return sqrt(max(f, 0.0f)); }
float sqr(float f) { return f * f; }

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

/**
 * Adapted from blender/intern/cycles/kernel/osl/cycles_osl_shaders/node_mapping.osl
 */
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

/**
 * Taken from blender.
 * For more information and an explaination of the algorithm, see https://github.com/blender/blender/blob/594f47ecd2d5367ca936cf6fc6ec8168c2b360d0/intern/cycles/kernel/kernel_montecarlo.h#L196
 */
float3 ensure_valid_reflection(float3 Ng, float3 I, float3 N) {
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

template<typename T>
T interpolate(T a, T b, T c, float2 barycentric) {
    float u = barycentric.x;
    float v = barycentric.y;
    float w = 1.0f - u - v;
    
    return a * u + b * v + c * w;
}

float safe_divide(float a, float b, float fallback) {
    return select(a / b, fallback, b == 0);
}

float3 safe_divide(float3 a, float3 b, float3 fallback) {
    return select(a / b, fallback, b == 0);
}
