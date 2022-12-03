#include <bridge/common.hpp>
#include <device/utils/warp.hpp>

kernel void normalizeEnvironmentMap(
    device float &sum [[buffer(0)]],
    device float *pdfs [[buffer(1)]],
    uint threadIndex [[thread_position_in_grid]],
    uint gridSize [[threads_per_grid]]
) {
    pdfs[threadIndex] *= gridSize * warp::uniformSquareToSpherePdf() / sum;
}
