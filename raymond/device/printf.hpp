#pragma once
#include <bridge/printf.hpp>

namespace _printf_internal {

size_t strlen(constant char *str) {
    size_t len = 0;
    while (*str++) len++;
    return len;
}

device char *strcpy(device char *dest, constant char *src) {
    do {
        *dest++ = *src;
    } while (*src++);
    return dest;
}

template<typename T>
device char *write(device char *dest, T t) {
    thread char *src = (thread char *)&t;
    for (size_t i = 0; i < sizeof(T); ++i)
        *dest++ = *src++;
    return dest;
}

template<typename T>
struct Tag {
    constant static printf_tag value = 0;
};

template<> struct Tag<long> { constant static printf_tag value = PRINTF_TAG_INT; };
template<> struct Tag<float> { constant static printf_tag value = PRINTF_TAG_FLOAT; };
template<> struct Tag<constant char *> { constant static printf_tag value = PRINTF_TAG_STRING; };

template<typename T>
struct TypeTransform { typedef void Target; };

template<typename P>
struct TypeTransform<device P *> { typedef long Target; };

#define map_type(from, to) \
template<> \
struct TypeTransform<from> { typedef to Target; };

map_type(bool, long)
map_type(char, long)
map_type(uchar, long)
map_type(short, long)
map_type(ushort, long)
map_type(int, long)
map_type(uint, long)
map_type(long, long)
map_type(ulong, long)

map_type(half, float)
map_type(float, float)

#undef map_type

int num_arguments() { return 0; }

template<typename T>
int num_arguments(T t) { return 1; }

template<typename T, typename... Args>
int num_arguments(T t, Args... args) { return num_arguments(t) + num_arguments(args...); }

size_t sizeof_arguments() {
    return 0;
}

template<typename T>
size_t sizeof_arguments(T t) {
    return sizeof(printf_tag) + sizeof(typename TypeTransform<T>::Target);
}

template<>
size_t sizeof_arguments(constant char *str) {
    return sizeof(printf_tag) + strlen(str) + 1;
}

template<typename T, typename... Args>
size_t sizeof_arguments(T t, Args... args) {
    return sizeof_arguments(t) + sizeof_arguments(args...);
}

device char *dump_arguments(device char *addr) {
    return addr;
}

template<typename T>
device char *dump_arguments(device char *addr, T t) {
    addr = write(addr, Tag<typename TypeTransform<T>::Target>::value);
    addr = write(addr, typename TypeTransform<T>::Target(t));
    return addr;
}

template<>
device char *dump_arguments(device char *addr, constant char *str) {
    addr = write(addr, Tag<constant char *>::value);
    addr = strcpy((device char *)addr, str);
    return addr;
}

template<typename T, typename... Args>
device char *dump_arguments(device char *addr, T t, Args... args) {
    addr = dump_arguments(addr, t);
    addr = dump_arguments(addr, args...);
    return addr;
}

struct printf_buffer {
private:
    uint32_t size;
    metal::atomic<uint32_t> index;
    char data;
    
public:
    template<typename... Args>
    int operator()(constant char *fmt, Args... args) device {
        const size_t packetSize = (strlen(fmt) + 1) + sizeof(int) + sizeof_arguments(args...);
        const int nargs = num_arguments(args...);
        
        if (atomic_load_explicit(&index, memory_order_relaxed) >= size)
            return 0;
        
        const int packetIndex = atomic_fetch_add_explicit(&index, (int)packetSize, metal::memory_order_relaxed);
        if (packetIndex + packetSize > (unsigned long)size)
            return 0;
        
        device char *addr = &data + packetIndex;
        addr = strcpy(addr, fmt);
        addr = write(addr, nargs);
        dump_arguments(addr, args...);
        return nargs;
    }
};

}

constant uint64_t printf_buffer_addr [[function_constant(PrintfBufferConstantIndex)]];

template<typename... Args>
int printf(constant char *fmt, Args... args) {
    device auto &printf_buffer = *(device _printf_internal::printf_buffer *)printf_buffer_addr;
    return printf_buffer(fmt, args...);
}

#undef assert
#define assert(condition) do { \
  if (!(condition)) \
    printf("Assertion failed: (%s), function %s, file %s, line %d.\n", #condition, __func__, __FILE__, __LINE__); \
} while (0)
