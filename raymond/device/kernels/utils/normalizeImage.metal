//
//  normalizeImage.metal
//  raymond
//
//  Created by Alexander Rath on 04.12.22.
//

#include <metal_stdlib>
using namespace metal;

kernel void normalizeImage(
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 coordinates [[thread_position_in_grid]]
) {
    output.write(float4(uniforms.exposure * input.read(coordinates).xyz / (uniforms.frameIndex + 1), 1), coordinates);
}
