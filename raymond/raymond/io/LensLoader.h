#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface Lens : NSObject

@property NSString *name;
@property uint32_t numSurfaces;
@property id<MTLBuffer> buffer;

@end

@interface LensLoader : NSObject

- (Lens *)load:(NSURL *)url device:(id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
