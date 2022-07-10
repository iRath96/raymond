#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLYReader : NSObject

- (instancetype)initWithURL:(NSURL *)url;
- (void)assertLine:(NSString *)string;
- (void)assertToken:(NSString *)string;
- (void)readLine;
- (int)readInt;

- (void)close;
- (void)reopen;

- (void)readVertexElements:(unsigned int)number vertices:(float * _Nonnull * _Nonnull)vertices normals:(float * _Nonnull * _Nonnull)normals texCoords:(float * _Nonnull * _Nonnull)texCoords;
- (void)readFaces:(unsigned int)number indices:(unsigned int * _Nonnull * _Nonnull)indices materials:(unsigned int * _Nonnull * _Nonnull)materials fromPalette:(const unsigned int * _Nonnull)palette;

@end

NS_ASSUME_NONNULL_END
