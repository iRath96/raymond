#import <Foundation/Foundation.h>
#include "SkyLoader.h"
#include "sky_model.h"

@implementation SkyLoader {
}

+ (void)generateTexture:(id<MTLTexture>)texture withOptions:(SkyOptions)options {
    int stride = 4;
    int bytesPerRow = stride * sizeof(float) * int(texture.width);
    float *pixels = (float *)malloc(bytesPerRow * texture.height);
    
    SKY_nishita_skymodel_precompute_texture(
        pixels, stride,
        0, int(texture.height), int(texture.width), int(texture.height),
        options.sunElevation, options.altitude,
        options.airDensity, options.dustDensity,
        options.ozoneDensity
    );
    
    [texture
        replaceRegion:MTLRegionMake2D(0, 0, texture.width, texture.height)
        mipmapLevel:0
        withBytes:pixels
        bytesPerRow:bytesPerRow];
}

+ (void)generateData:(float *)data withOptions:(SkyOptions)options {
    SKY_nishita_skymodel_precompute_sun(
        options.sunElevation, options.sunSize,
        options.altitude, options.airDensity, options.dustDensity,
        data+0, data+3
    );
    
    data[6] = options.sunElevation;
    data[7] = options.sunRotation;
    data[8] = options.sunDisc ? options.sunSize : -1.0f;
    data[9] = options.sunIntensity;
}

@end
