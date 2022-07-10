#import "PLYReader.h"
#include <stdio.h>

@implementation PLYReader {
    NSString *path;
    FILE *file;
    long offset;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (!self) return self;
    
    path = url.relativePath;
    
    const char *cpath = [path cStringUsingEncoding:NSASCIIStringEncoding];
    file = fopen(cpath, "r");
    if (file == NULL) {
        printf("could not open '%s'\n", cpath);
        assert(false);
    }
    
    return self;
}

- (void)readLine {
    static char buffer[4096];
    fgets(buffer, 4096, file);
}

- (void)assertLine:(NSString *)string {
    static char buffer[4096];
    fgets(buffer, 4096, file);
    buffer[strcspn(buffer, "\n")] = 0;
    
    assert(strcmp([string cStringUsingEncoding:NSASCIIStringEncoding], buffer) == 0);
}

- (void)assertToken:(NSString *)string {
    static char buffer[4096];
    fscanf(file, "%s ", buffer);
    
    assert(strcmp([string cStringUsingEncoding:NSASCIIStringEncoding], buffer) == 0);
}

- (int)readInt {
    int value;
    fscanf(file, "%d\n", &value);
    return value;
}

- (void)close {
    offset = ftell(file);
    fclose(file);
}

- (void)reopen {
    const char *cpath = [path cStringUsingEncoding:NSASCIIStringEncoding];
    file = fopen(cpath, "r");
    fseek(file, offset, SEEK_SET);
}

- (void)readVertexElements:(unsigned int)number vertices:(float * _Nonnull *)vertices normals:(float * _Nonnull *)normals texCoords:(float * _Nonnull *)texCoords {
    for (int i = 0; i < number; ++i) {
        fscanf(file, "%f %f %f %f %f %f %f %f\n",
            *vertices+0, *vertices+1, *vertices+2,
            *normals+0, *normals+1, *normals+2,
            *texCoords+0, *texCoords+1
        );
        
        *vertices += 3;
        *normals += 3;
        *texCoords += 2;
    }
}

- (void)readFaces:(unsigned int)number indices:(unsigned int * _Nonnull *)indices materials:(unsigned int * _Nonnull *)materials fromPalette:(const unsigned int *)palette {
    for (int i = 0; i < number; ++i) {
        int numIndices;
        fscanf(file, "%d %d %d %d %d\n",
            &numIndices,
            *indices+0, *indices+1, *indices+2,
            *materials
        );
        
        assert(numIndices == 3);
        
        **materials = palette[**materials];
        
        *indices += 3;
        *materials += 1;
    }
}

@end
