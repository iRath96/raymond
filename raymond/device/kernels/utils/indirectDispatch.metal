#include <bridge/common.hpp>

kernel void makeIndirectDispatchArguments(
    device uint *rayCount [[buffer(0)]],
    device MTLDispatchThreadgroupsIndirectArguments *dispatchArg [[buffer(1)]]
) {
    dispatchArg->threadgroupsPerGrid[0] = (*rayCount + 63) / 64;
    dispatchArg->threadgroupsPerGrid[1] = 1;
    dispatchArg->threadgroupsPerGrid[2] = 1;
}
