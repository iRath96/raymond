#include "../../../bridge/common.hpp"

kernel void reduceEnvironmentMap(
    device float *mipmap [[buffer(0)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 gridSize [[threads_per_grid]]
) {
    const int inputIndex = threadIndex.y * gridSize.x + threadIndex.x;
    const int gridLength = gridSize.x * gridSize.y;
    
    float sum = 0;
    for (int i = 0; i < 4; ++i) {
        sum += mipmap[gridLength + 4 * inputIndex + i];
    }
    for (int i = 0; i < 4; ++i) {
        mipmap[gridLength + 4 * inputIndex + i] /= sum;
    }
    
    const uint2 quadPosition = threadIndex / 2;
    const uint2 quadGridSize = gridSize / 2;
    const uint quadIndex = quadPosition.y * quadGridSize.x + quadPosition.x;
    const uint outputIndex = 4 * quadIndex + (threadIndex.x & 1) + 2 * (threadIndex.y & 1);
    mipmap[outputIndex] = sum;
}
