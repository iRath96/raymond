#pragma once

#include "ShaderTypes.h"

/**
 * \brief Generate fast and reasonably good pseudorandom numbers using the
 * Tiny Encryption Algorithm (TEA) by David Wheeler and Roger Needham.
 *
 * For details, refer to "GPU Random Numbers via the Tiny Encryption Algorithm"
 * by Fahad Zafar, Marc Olano, and Aaron Curtis.
 *
 * \param v0
 *     First input value to be encrypted (could be the sample index)
 * \param v1
 *     Second input value to be encrypted (e.g. the requested random number dimension)
 * \param rounds
 *     How many rounds should be executed? The default for random number
 *     generation is 4.
 * \return
 *     A uniformly distributed 32-bit integer
 */
uint32_t sample_tea_32(uint32_t v0, uint32_t v1, int rounds = 6) {
    uint32_t sum = 0;

    for (int i = 0; i < rounds; ++i) {
        sum += 0x9e3779b9;
        v0 += ((v1 << 4) + 0xa341316c) ^ (v1 + sum) ^ ((v1 >> 5) + 0xc8013ea4);
        v1 += ((v0 << 4) + 0xad90777d) ^ (v0 + sum) ^ ((v0 >> 5) + 0x7e95761e);
    }

    return v1;
}

/**
 * \brief Generate fast and reasonably good pseudorandom numbers using the
 * Tiny Encryption Algorithm (TEA) by David Wheeler and Roger Needham.
 *
 * This function uses \ref sample_tea to return single precision floating point
 * numbers on the interval <tt>[0, 1)</tt>
 *
 * \param v0
 *     First input value to be encrypted (could be the sample index)
 * \param v1
 *     Second input value to be encrypted (e.g. the requested random number dimension)
 * \param rounds
 *     How many rounds should be executed? The default for random number
 *     generation is 4.
 * \return
 *     A uniformly distributed floating point number on the interval <tt>[0, 1)</tt>
 */
float sample_tea_float32(uint32_t v0, uint32_t v1, int rounds = 6) {
    union {
        uint32_t raw;
        float f;
    } v;
    v.raw = (sample_tea_32(v0, v1, rounds) >> 9) | 0x3f800000u;
    return v.f - 1.f;
}

float sample1d(device PRNGState &prng) {
    return sample_tea_float32(prng.seed, prng.index++);
}

float2 sample2d(device PRNGState &prng) {
    return float2(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}

float3 sample3d(device PRNGState &prng) {
    return float3(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}

float3 sample3d(thread PRNGState &prng) {
    return float3(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}
