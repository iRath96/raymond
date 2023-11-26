#pragma once

#include <bridge/common.hpp>
#include <device/utils/math.hpp>
#include <device/utils/warp.hpp>

typedef struct WorldLight {
    MaterialIndex shaderIndex [[ id(0) ]];
    
    int resolution [[ id(1) ]]; // must be a power of two
    device float *pdfs [[ id(2) ]];
    device float *mipmap [[ id(3) ]];
    
    float pdf(float3 wo) const device {
        uint2 position = uint2(resolution * warp::uniformSphereToSquare(wo)) % resolution;
        return pdfs[position.y * resolution + position.x];
    }
    
    float3 sample(float2 uv, thread float &pdf) const device {
        int currentResolution = 1;
        int2 shift = 0;
        
        device float *currentLevel = mipmap;
        while (currentResolution < resolution) {
            const int currentOffset = 4 * (shift.y * currentResolution + shift.x);
            
            currentLevel += currentResolution * currentResolution;
            shift *= 2;
            currentResolution *= 2;
            
            const float topLeft = currentLevel[currentOffset+0];
            const float topRight = currentLevel[currentOffset+1];
            const float bottomLeft = currentLevel[currentOffset+2];
            
            const float leftProb = topLeft + bottomLeft;
            float topProb;
            if (uv.x < leftProb) {
                // left
                const float invProb = 1 / leftProb;
                uv.x *= invProb;
                topProb = topLeft * invProb;
            } else {
                // right
                const float invProb = 1 / (1 - leftProb);
                uv.x = (uv.x - leftProb) * invProb;
                topProb = topRight * invProb;
                shift.x += 1;
            }
            
            if (uv.y < topProb) {
                // top
                uv.y /= topProb;
            } else {
                uv.y = (uv.y - topProb) / (1 - topProb);
                shift.y += 1;
            }
        }
        
        pdf = pdfs[shift.y * resolution + shift.x];
        uv = (float2(shift) + uv) / resolution;
        return warp::uniformSquareToSphere(uv);
    }
} WorldLight;
