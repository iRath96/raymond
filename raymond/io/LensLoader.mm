#import "LensLoader.h"
#include <iostream>

#include <lore/io/LensReader.h>
#include <lore/analysis/Paraxial.h>
#include <lore/logging.h>
#include <fstream>

@implementation Lens {
}

@end

@implementation LensLoader {
}

- (int)loadGlassCatalog:(NSURL *)url {
    return lore::GlassCatalog::shared.read([url.path cStringUsingEncoding:NSASCIIStringEncoding]);
}

- (Lens *)load:(NSURL *)url device:(id<MTLDevice>)device {
    std::ifstream file { [url.path cStringUsingEncoding:NSASCIIStringEncoding] };
    
    lore::io::LensReader reader;
    auto lensScheme = reader.read(file).front();
    auto lens = lensScheme.lens<float>();
    auto &surfaces = lens.surfaces;
    
    lore::log::info() << "loaded lens " << lensScheme.name << " with " << lens.surfaces.size() << " surfaces" << std::flush;
    
    Lens *result = [Lens new];
    result.name = [NSString stringWithCString:lensScheme.name.c_str() encoding:NSASCIIStringEncoding];
    result.numSurfaces = uint32_t(lens.surfaces.size());
    result.buffer = [device newBufferWithBytes:surfaces.data() length:sizeof(surfaces[0]) * surfaces.size() options:MTLStorageModeManaged];
    result.stopIndex = lensScheme.stopIndex;
    
    auto analysis = lore::ParaxialAnalysis<float>(lens, lensScheme.wavelengths.front().wavelength);
    result.efl = analysis.efl;
    result.fstop = analysis.efl / (2 * lensScheme.entranceBeamRadius);
    
    return result;
}

@end
