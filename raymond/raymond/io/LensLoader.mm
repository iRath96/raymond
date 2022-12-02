#import "LensLoader.h"
#include <iostream>

#include <lore/io/LensReader.h>
#include <fstream>

@implementation Lens {
}

@end

@implementation LensLoader {
}

- (Lens *)load:(NSURL *)url device:(id<MTLDevice>)device {
    std::ifstream file { [url.path cStringUsingEncoding:NSASCIIStringEncoding] };
    
    lore::io::LensReader reader;
    auto lens = reader.read(file).front();
    auto &surfaces = lens.surfaces;
    
    std::cout << "loaded lens " << lens.name << " with " << lens.surfaces.size() << " surfaces" << std::endl;
    
    Lens *result = [Lens new];
    result.name = [NSString stringWithCString:lens.name.c_str() encoding:NSASCIIStringEncoding];
    result.numSurfaces = uint32_t(lens.surfaces.size());
    result.buffer = [device newBufferWithBytes:surfaces.data() length:sizeof(surfaces[0]) * surfaces.size() options:MTLStorageModeManaged];
    return result;
}

@end
