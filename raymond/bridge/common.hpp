#pragma once

#ifdef __METAL_VERSION__

// MARK: Metal

#include <metal_stdlib>
using namespace metal;

#define DEVICE_STRUCT(name) struct name

#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
typedef packed_float3 MPSPackedFloat3;

#else

// MARK: - Swift/Obj-C

#include <simd/simd.h>
#import <Foundation/Foundation.h>

/// Avoid cluttering the global namespace by prefix names of structs with `Device` on the host
#define DEVICE_STRUCT(name) struct Device##name

/// Use Metal names for SIMD Types
typedef simd_float2 float2;
typedef simd_float3 float3;
typedef simd_float4 float4;
typedef simd_float3x3 float3x3;
typedef simd_float3x4 float3x4;
typedef simd_float4x4 float4x4;

typedef uint32_t atomic_uint;

/// Support half type on the host using clang extensions
typedef __fp16 half;
typedef __attribute__((__ext_vector_type__(3))) half half3;

/// Support packed float3 on the host
typedef struct _MPSPackedFloat3 {
    union {
        struct {
            float x;
            float y;
            float z;
        };
        float elements[3];
    };
} MPSPackedFloat3;

#endif

// MARK: - Common

typedef MPSPackedFloat3 Vertex;
typedef MPSPackedFloat3 Normal;
typedef simd_float2 TexCoord;
typedef uint32_t VertexIndex;
typedef uint32_t FaceIndex;
typedef uint32_t LightIndex;
typedef uint32_t PrimitiveIndex;
typedef uint32_t InstanceIndex;
typedef uint16_t MaterialIndex;

typedef struct {
    union {
        struct {
            VertexIndex x;
            VertexIndex y;
            VertexIndex z;
        };
        VertexIndex elements[3];
    };
} IndexTriplet;

// MARK: - Forward declarations

#ifdef __METAL_VERSION__

struct Context;
struct ShadingContext;
struct LightSample;
struct BsdfSample;
struct PrngState;

#endif
