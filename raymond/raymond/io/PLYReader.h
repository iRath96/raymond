#import <Foundation/Foundation.h>
#import <simd/simd.h>
#include "../bridge/common.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface PLYReader : NSObject

- (instancetype)initWithURL:(NSURL *)url;
- (void)assertLine:(NSString *)string;
- (void)assertToken:(NSString *)string;
- (void)readLine;
- (int)readInt;

- (void)close;
- (void)reopen;

- (void)readVertexElements:(unsigned int)number
    vertices:(Vertex * _Nonnull)vertices
    normals:(Normal * _Nonnull)normals
    texCoords:(TexCoord * _Nonnull)texCoords
    boundsMin:(simd_float3 *)boundsMin
    boundsMax:(simd_float3 *)boundsMax;

- (void)readFaces:(unsigned int)number
    vertices:(Vertex * _Nonnull)vertices
    indices:(IndexTriplet * _Nonnull)indices
    materials:(MaterialIndex * _Nonnull)materials
    fromPalette:(const MaterialIndex * _Nonnull)palette;

@end

NS_ASSUME_NONNULL_END
