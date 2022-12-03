#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    float sunElevation;
    float sunRotation;
    bool sunDisc;
    float sunSize;
    float sunIntensity;
    float altitude;
    float airDensity;
    float dustDensity;
    float ozoneDensity;
} SkyOptions;

@interface SkyLoader : NSObject

+ (void)generateTexture:(id<MTLTexture>)texture withOptions:(SkyOptions)options;
+ (void)generateData:(float *)data withOptions:(SkyOptions)options;

@end

NS_ASSUME_NONNULL_END
