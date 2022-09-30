#pragma once

#include <metal_stdlib>
using namespace metal;

// combined from varies sources in Blender

// MARK: - hash functions

/* ***** Jenkins Lookup3 Hash Functions ***** */
/* Source: http://burtleburtle.net/bob/c/lookup3.c */

#define rot(x, k) (((x) << (k)) | ((x) >> (32 - (k))))

#define mix(a, b, c) \
  { \
    a -= c; \
    a ^= rot(c, 4); \
    c += b; \
    b -= a; \
    b ^= rot(a, 6); \
    a += c; \
    c -= b; \
    c ^= rot(b, 8); \
    b += a; \
    a -= c; \
    a ^= rot(c, 16); \
    c += b; \
    b -= a; \
    b ^= rot(a, 19); \
    a += c; \
    c -= b; \
    c ^= rot(b, 4); \
    b += a; \
  } \
  ((void)0)

#define final(a, b, c) \
  { \
    c ^= b; \
    c -= rot(b, 14); \
    a ^= c; \
    a -= rot(c, 11); \
    b ^= a; \
    b -= rot(a, 25); \
    c ^= b; \
    c -= rot(b, 16); \
    a ^= c; \
    a -= rot(c, 4); \
    b ^= a; \
    b -= rot(a, 14); \
    c ^= b; \
    c -= rot(b, 24); \
  } \
  ((void)0)

uint hash_uint(uint kx) {
  uint a, b, c;
  a = b = c = 0xdeadbeef + (1 << 2) + 13;

  a += kx;
  final(a, b, c);

  return c;
}

uint hash_uint2(uint kx, uint ky) {
  uint a, b, c;
  a = b = c = 0xdeadbeef + (2 << 2) + 13;

  b += ky;
  a += kx;
  final(a, b, c);

  return c;
}

uint hash_uint3(uint kx, uint ky, uint kz) {
  uint a, b, c;
  a = b = c = 0xdeadbeef + (3 << 2) + 13;

  c += kz;
  b += ky;
  a += kx;
  final(a, b, c);

  return c;
}

uint hash_uint4(uint kx, uint ky, uint kz, uint kw) {
  uint a, b, c;
  a = b = c = 0xdeadbeef + (4 << 2) + 13;

  a += kx;
  b += ky;
  c += kz;
  mix(a, b, c);

  a += kw;
  final(a, b, c);

  return c;
}

#undef rot
#undef final
#undef mix

// MARK: - utility functions

int float_to_int(float f) {
  return (int)f;
}

uint32_t float_as_uint(float f) {
  union {
    uint32_t i;
    float f;
  } u;
  u.f = f;
  return u.i;
}

float hash_uint_to_float(uint kx) {
  return (float)hash_uint(kx) / (float)0xFFFFFFFFu;
}

float hash_uint2_to_float(uint kx, uint ky) {
  return (float)hash_uint2(kx, ky) / (float)0xFFFFFFFFu;
}

float hash_uint3_to_float(uint kx, uint ky, uint kz) {
  return (float)hash_uint3(kx, ky, kz) / (float)0xFFFFFFFFu;
}

float hash_uint4_to_float(uint kx, uint ky, uint kz, uint kw) {
  return (float)hash_uint4(kx, ky, kz, kw) / (float)0xFFFFFFFFu;
}

float hash_float_to_float(float k) {
  return hash_uint_to_float(
    float_as_uint(k));
}

float hash_float2_to_float(float2 k) {
  return hash_uint2_to_float(
    float_as_uint(k.x), float_as_uint(k.y));
}

float hash_float3_to_float(float3 k) {
  return hash_uint3_to_float(
    float_as_uint(k.x), float_as_uint(k.y), float_as_uint(k.z));
}

float hash_float4_to_float(float4 k) {
  return hash_uint4_to_float(
      float_as_uint(k.x), float_as_uint(k.y),
      float_as_uint(k.z), float_as_uint(k.w));
}

int quick_floor_to_int(float x) {
  return float_to_int(x) - ((x < 0) ? 1 : 0);
}

float floorfrac(float x, thread int *i) {
  *i = quick_floor_to_int(x);
  return x - *i;
}

// MARK: - perlin noise

float fade(float t) {
  return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

float negate_if(float val, int condition) {
  return (condition) ? -val : val;
}

float grad1(int hash, float x) {
  int h = hash & 15;
  float g = 1 + (h & 7);
  return negate_if(g, h & 8) * x;
}

float perlin_1d(float x) {
  int X;
  float fx = floorfrac(x, &X);
  float u = fade(fx);

  return mix(grad1(hash_uint(X), fx), grad1(hash_uint(X + 1), fx - 1.0f), u);
}

float bi_mix(float v0, float v1, float v2, float v3, float x, float y)
{
  float x1 = 1.0f - x;
  return (1.0f - y) * (v0 * x1 + v1 * x) + y * (v2 * x1 + v3 * x);
}

float tri_mix(float v0,
              float v1,
              float v2,
              float v3,
              float v4,
              float v5,
              float v6,
              float v7,
              float x,
              float y,
              float z) {
  float x1 = 1.0f - x;
  float y1 = 1.0f - y;
  float z1 = 1.0f - z;
  return z1 * (y1 * (v0 * x1 + v1 * x) + y * (v2 * x1 + v3 * x)) +
         z * (y1 * (v4 * x1 + v5 * x) + y * (v6 * x1 + v7 * x));
}

float quad_mix(float v0,
               float v1,
               float v2,
               float v3,
               float v4,
               float v5,
               float v6,
               float v7,
               float v8,
               float v9,
               float v10,
               float v11,
               float v12,
               float v13,
               float v14,
               float v15,
               float x,
               float y,
               float z,
               float w) {
  return mix(tri_mix(v0, v1, v2, v3, v4, v5, v6, v7, x, y, z),
             tri_mix(v8, v9, v10, v11, v12, v13, v14, v15, x, y, z),
             w);
}

float grad2(int hash, float x, float y) {
  int h = hash & 7;
  float u = h < 4 ? x : y;
  float v = 2.0f * (h < 4 ? y : x);
  return negate_if(u, h & 1) + negate_if(v, h & 2);
}

float grad3(int hash, float x, float y, float z) {
  int h = hash & 15;
  float u = h < 8 ? x : y;
  float vt = ((h == 12) || (h == 14)) ? x : z;
  float v = h < 4 ? y : vt;
  return negate_if(u, h & 1) + negate_if(v, h & 2);
}

float grad4(int hash, float x, float y, float z, float w) {
  int h = hash & 31;
  float u = h < 24 ? x : y;
  float v = h < 16 ? y : z;
  float s = h < 8 ? z : w;
  return negate_if(u, h & 1) + negate_if(v, h & 2) + negate_if(s, h & 4);
}

float perlin_2d(float x, float y) {
  int X;
  int Y;

  float fx = floorfrac(x, &X);
  float fy = floorfrac(y, &Y);

  float u = fade(fx);
  float v = fade(fy);

  float r = bi_mix(grad2(hash_uint2(X, Y), fx, fy),
                   grad2(hash_uint2(X + 1, Y), fx - 1.0f, fy),
                   grad2(hash_uint2(X, Y + 1), fx, fy - 1.0f),
                   grad2(hash_uint2(X + 1, Y + 1), fx - 1.0f, fy - 1.0f),
                   u,
                   v);

  return r;
}

float perlin_3d(float x, float y, float z) {
  int X;
  int Y;
  int Z;

  float fx = floorfrac(x, &X);
  float fy = floorfrac(y, &Y);
  float fz = floorfrac(z, &Z);

  float u = fade(fx);
  float v = fade(fy);
  float w = fade(fz);

  float r = tri_mix(grad3(hash_uint3(X, Y, Z), fx, fy, fz),
                    grad3(hash_uint3(X + 1, Y, Z), fx - 1.0f, fy, fz),
                    grad3(hash_uint3(X, Y + 1, Z), fx, fy - 1.0f, fz),
                    grad3(hash_uint3(X + 1, Y + 1, Z), fx - 1.0f, fy - 1.0f, fz),
                    grad3(hash_uint3(X, Y, Z + 1), fx, fy, fz - 1.0f),
                    grad3(hash_uint3(X + 1, Y, Z + 1), fx - 1.0f, fy, fz - 1.0f),
                    grad3(hash_uint3(X, Y + 1, Z + 1), fx, fy - 1.0f, fz - 1.0f),
                    grad3(hash_uint3(X + 1, Y + 1, Z + 1), fx - 1.0f, fy - 1.0f, fz - 1.0f),
                    u,
                    v,
                    w);
  return r;
}

float perlin_4d(float x, float y, float z, float w) {
  int X;
  int Y;
  int Z;
  int W;

  float fx = floorfrac(x, &X);
  float fy = floorfrac(y, &Y);
  float fz = floorfrac(z, &Z);
  float fw = floorfrac(w, &W);

  float u = fade(fx);
  float v = fade(fy);
  float t = fade(fz);
  float s = fade(fw);

  float r = quad_mix(
      grad4(hash_uint4(X, Y, Z, W), fx, fy, fz, fw),
      grad4(hash_uint4(X + 1, Y, Z, W), fx - 1.0f, fy, fz, fw),
      grad4(hash_uint4(X, Y + 1, Z, W), fx, fy - 1.0f, fz, fw),
      grad4(hash_uint4(X + 1, Y + 1, Z, W), fx - 1.0f, fy - 1.0f, fz, fw),
      grad4(hash_uint4(X, Y, Z + 1, W), fx, fy, fz - 1.0f, fw),
      grad4(hash_uint4(X + 1, Y, Z + 1, W), fx - 1.0f, fy, fz - 1.0f, fw),
      grad4(hash_uint4(X, Y + 1, Z + 1, W), fx, fy - 1.0f, fz - 1.0f, fw),
      grad4(hash_uint4(X + 1, Y + 1, Z + 1, W), fx - 1.0f, fy - 1.0f, fz - 1.0f, fw),
      grad4(hash_uint4(X, Y, Z, W + 1), fx, fy, fz, fw - 1.0f),
      grad4(hash_uint4(X + 1, Y, Z, W + 1), fx - 1.0f, fy, fz, fw - 1.0f),
      grad4(hash_uint4(X, Y + 1, Z, W + 1), fx, fy - 1.0f, fz, fw - 1.0f),
      grad4(hash_uint4(X + 1, Y + 1, Z, W + 1), fx - 1.0f, fy - 1.0f, fz, fw - 1.0f),
      grad4(hash_uint4(X, Y, Z + 1, W + 1), fx, fy, fz - 1.0f, fw - 1.0f),
      grad4(hash_uint4(X + 1, Y, Z + 1, W + 1), fx - 1.0f, fy, fz - 1.0f, fw - 1.0f),
      grad4(hash_uint4(X, Y + 1, Z + 1, W + 1), fx, fy - 1.0f, fz - 1.0f, fw - 1.0f),
      grad4(hash_uint4(X + 1, Y + 1, Z + 1, W + 1), fx - 1.0f, fy - 1.0f, fz - 1.0f, fw - 1.0f),
      u,
      v,
      t,
      s);

  return r;
}

// MARK: - other stuff

bool isfinite_safe(float f) {
  /* By IEEE 754 rule, 2*Inf equals Inf */
  uint32_t x = float_as_uint(f);
  return (f == f) && (x == 0 || x == (1u << 31) || (f != 2.0f * f)) && !((x << 1) > 0xff000000u);
}

float ensure_finite(float v) {
  return isfinite_safe(v) ? v : 0.0f;
}

float noise_scale1(float result) {
  return 0.2500f * result;
}

float noise_scale2(float result) {
  return 0.6616f * result;
}

float noise_scale3(float result) {
  return 0.9820f * result;
}

float noise_scale4(float result) {
  return 0.8344f * result;
}

float snoise(float p) {
  return noise_scale1(ensure_finite(perlin_1d(p)));
}

float noise(float p) {
  return 0.5f * snoise(p) + 0.5f;
}

float snoise(float2 p) {
  return noise_scale2(ensure_finite(perlin_2d(p.x, p.y)));
}

float noise(float2 p) {
  return 0.5f * snoise(p) + 0.5f;
}

float snoise(float3 p) {
  return noise_scale3(ensure_finite(perlin_3d(p.x, p.y, p.z)));
}

float noise(float3 p) {
  return 0.5f * snoise(p) + 0.5f;
}

float snoise(float4 p) {
  return noise_scale4(ensure_finite(perlin_4d(p.x, p.y, p.z, p.w)));
}

float noise(float4 p) {
  return 0.5f * snoise(p) + 0.5f;
}

// MARK: - fractal noise

template<typename T>
float fractal_noise(T p, float octaves, float roughness) {
  float fscale = 1.0f;
  float amp = 1.0f;
  float maxamp = 0.0f;
  float sum = 0.0f;
  octaves = clamp(octaves, 0.0f, 15.0f);
  int n = float_to_int(octaves);
  for (int i = 0; i <= n; i++) {
    float t = noise(fscale * p);
    sum += t * amp;
    maxamp += amp;
    amp *= clamp(roughness, 0.0f, 1.0f);
    fscale *= 2.0f;
  }
  float rmd = octaves - floor(octaves);
  if (rmd != 0.0f) {
    float t = noise(fscale * p);
    float sum2 = sum + t * amp;
    sum /= maxamp;
    sum2 /= maxamp + amp;
    return (1.0f - rmd) * sum + rmd * sum2;
  } else {
    return sum / maxamp;
  }
}
