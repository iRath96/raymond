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

float my_strtof(char *head, char **endPtr) {
    while (*head == ' ') ++head;
    
    bool isNegative = *head == '-';
    if (isNegative) head++;
    
    /// @todo perhaps switch to int?
    long decimal = 0;
    int baseExp = 0;
    bool hasSeenPoint = false;
    
    while (true) {
        char chr = *(head++);
        if (chr >= '0' && chr <= '9') {
            /// @todo handle overflows of 'decimal' gracefully, maybe by limiting number of digits read
            decimal *= 10;
            decimal += chr - '0';
            baseExp -= hasSeenPoint ? 1 : 0;
        } else if (chr == '.') {
            assert(!hasSeenPoint);
            hasSeenPoint = true;
        } else if (chr == ' ' || chr == '\n') {
            break;
        } else {
            assert(!"invalid character");
        }
    }
    
    *endPtr = head - 1;
    
    /// @todo is this precise enough?
    if (isNegative) decimal *= -1;
    return decimal * powf(10, baseExp);
}

- (void)readVertexElements:(unsigned int)number
    vertices:(float * _Nonnull)vertices
    normals:(float * _Nonnull)normals
    texCoords:(float * _Nonnull)texCoords
    boundsMin:(simd_float3 *)boundsMin
    boundsMax:(simd_float3 *)boundsMax
{
    char buffer[16384];
    long n = sizeof(buffer);
    char *threshold = buffer + sizeof(buffer) - 256;
    char *head = buffer + n;
    
    for (int i = 0; i < number; ++i) {
        if (head >= threshold) {
            fseek(file, (head - buffer) - n, SEEK_CUR);
            n = fread(buffer, 1, sizeof(buffer), file);
            head = buffer;
        }
        
        for (int j = 0; j < 3; ++j) {
            float value = my_strtof(head, &head);
            if (value < (*boundsMin)[j])
                (*boundsMin)[j] = value;
            else if (value > (*boundsMax)[j])
                (*boundsMax)[j] = value;
            *(vertices++) = value;
        }
        for (int j = 0; j < 3; ++j) *(normals++) = my_strtof(head, &head);
        for (int j = 0; j < 2; ++j) *(texCoords++) = my_strtof(head, &head);
        
        assert(*head == '\n');
        head++;
    }
    
    fseek(file, (head - buffer) - n, SEEK_CUR);
}

- (void)readFaces:(unsigned int)number
    indices:(unsigned int * _Nonnull)indices
    materials:(unsigned int * _Nonnull)materials
    fromPalette:(const unsigned int *)palette
{
    char buffer[16384];
    long n = sizeof(buffer);
    char *threshold = buffer + sizeof(buffer) - 256;
    char *head = buffer + n;
    
    for (int i = 0; i < number; ++i) {
        if (head >= threshold) {
            fseek(file, (head - buffer) - n, SEEK_CUR);
            n = fread(buffer, 1, sizeof(buffer), file);
            head = buffer;
        }
        
        int numIndices = (int)strtol(head, &head, 10);
        for (int j = 0; j < 3; ++j) *(indices++) = (int)strtol(head, &head, 10);
        *materials = (int)strtol(head, &head, 10);
        
        assert(numIndices == 3);
        
        *materials = palette[*materials];
        materials++;
    }
}

@end
