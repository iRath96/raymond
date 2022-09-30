#include "../../bridge/common.hpp"
#include "../lights/Lights.hpp"
#include "../ShadingContext.hpp"
#include "../Context.hpp"

void Lights::evaluateEnvironment(device Context &ctx, thread ShadingContext &shading) const device {
    shading.position = shading.wo;
    shading.normal = shading.wo;
    shading.trueNormal = shading.wo; /// @todo ???
    shading.generated = -shading.wo;
    shading.object = -shading.wo;
    shading.uv = 0;
    
    shadeLight(worldLight.shaderIndex, ctx, shading);
}
