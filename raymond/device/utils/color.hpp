#pragma once

float luminance(float3 color) {
    // ITU-R standard
    return dot(float3(0.2126, 0.7152, 0.0722), color);
}

// adapted from blender/intern/cycles/util/color.h
float3 rgb2hsv(float3 rgb) {
    const float cmax = max(rgb.x, max(rgb.y, rgb.z));
    const float cmin = min(rgb.x, min(rgb.y, rgb.z));
    const float cdelta = cmax - cmin;

    float h = 0;
    float s = 0;
    float v = cmax;

    if (cmax != 0) {
        s = cdelta / cmax;
    }

    if (s != 0) {
        const float3 c = (cmax - rgb) / cdelta;

        if (rgb.x == cmax) {
            h = 0 + c.z - c.y;
        } else if (rgb.y == cmax) {
            h = 2 + c.x - c.z;
        } else {
            h = 4 + c.y - c.x;
        }
        
        h /= 6;
    
        if (h < 0) {
            h += 1;
        }
    }

    return float3(h, s, v);
}

float3 hsv2rgb(float3 hsv) {
    float h = hsv.x;
    const float s = hsv.y;
    const float v = hsv.z;
    
    if (s == 0) {
        return float3(v, v, v);
    }

    if (h == 1) {
        h = 0;
    }

    h *= 6;
    
    const float i = floor(h);
    const float f = h - i;
    const float p = v * (1 - s);
    const float q = v * (1 - (s * f));
    const float t = v * (1 - (s * (1 - f)));

    switch (int(i)) {
    case 0: return float3(v, t, p);
    case 1: return float3(q, v, p);
    case 2: return float3(p, v, t);
    case 3: return float3(p, q, v);
    case 4: return float3(t, p, v);
    default: return float3(v, p, q);
    }
}

float3 xyz_to_rgb(float3 xyz) {
    return float3(3.240479 * xyz.x + -1.537150 * xyz.y + -0.498535 * xyz.z,
                 -0.969256 * xyz.x +  1.875991 * xyz.y +  0.041556 * xyz.z,
                  0.055648 * xyz.x + -0.204043 * xyz.y +  1.057311 * xyz.z);
}

float3 xyY_to_xyz(float x, float y, float Y) {
    float X, Z;

    if (y != 0) {
        X = (x / y) * Y;
    } else {
        X = 0;
    }

    if (y != 0 && Y != 0) {
        Z = (1 - x - y) / y * Y;
    } else {
        Z = 0;
    }

    return float3(X, Y, Z);
}

// taken from blender/imbuf/intern/colormanagement.c
static constant float3 cie_colour_match[81] = {
    {0.0014f, 0.0000f, 0.0065f}, {0.0022f, 0.0001f, 0.0105f}, {0.0042f, 0.0001f, 0.0201f},
    {0.0076f, 0.0002f, 0.0362f}, {0.0143f, 0.0004f, 0.0679f}, {0.0232f, 0.0006f, 0.1102f},
    {0.0435f, 0.0012f, 0.2074f}, {0.0776f, 0.0022f, 0.3713f}, {0.1344f, 0.0040f, 0.6456f},
    {0.2148f, 0.0073f, 1.0391f}, {0.2839f, 0.0116f, 1.3856f}, {0.3285f, 0.0168f, 1.6230f},
    {0.3483f, 0.0230f, 1.7471f}, {0.3481f, 0.0298f, 1.7826f}, {0.3362f, 0.0380f, 1.7721f},
    {0.3187f, 0.0480f, 1.7441f}, {0.2908f, 0.0600f, 1.6692f}, {0.2511f, 0.0739f, 1.5281f},
    {0.1954f, 0.0910f, 1.2876f}, {0.1421f, 0.1126f, 1.0419f}, {0.0956f, 0.1390f, 0.8130f},
    {0.0580f, 0.1693f, 0.6162f}, {0.0320f, 0.2080f, 0.4652f}, {0.0147f, 0.2586f, 0.3533f},
    {0.0049f, 0.3230f, 0.2720f}, {0.0024f, 0.4073f, 0.2123f}, {0.0093f, 0.5030f, 0.1582f},
    {0.0291f, 0.6082f, 0.1117f}, {0.0633f, 0.7100f, 0.0782f}, {0.1096f, 0.7932f, 0.0573f},
    {0.1655f, 0.8620f, 0.0422f}, {0.2257f, 0.9149f, 0.0298f}, {0.2904f, 0.9540f, 0.0203f},
    {0.3597f, 0.9803f, 0.0134f}, {0.4334f, 0.9950f, 0.0087f}, {0.5121f, 1.0000f, 0.0057f},
    {0.5945f, 0.9950f, 0.0039f}, {0.6784f, 0.9786f, 0.0027f}, {0.7621f, 0.9520f, 0.0021f},
    {0.8425f, 0.9154f, 0.0018f}, {0.9163f, 0.8700f, 0.0017f}, {0.9786f, 0.8163f, 0.0014f},
    {1.0263f, 0.7570f, 0.0011f}, {1.0567f, 0.6949f, 0.0010f}, {1.0622f, 0.6310f, 0.0008f},
    {1.0456f, 0.5668f, 0.0006f}, {1.0026f, 0.5030f, 0.0003f}, {0.9384f, 0.4412f, 0.0002f},
    {0.8544f, 0.3810f, 0.0002f}, {0.7514f, 0.3210f, 0.0001f}, {0.6424f, 0.2650f, 0.0000f},
    {0.5419f, 0.2170f, 0.0000f}, {0.4479f, 0.1750f, 0.0000f}, {0.3608f, 0.1382f, 0.0000f},
    {0.2835f, 0.1070f, 0.0000f}, {0.2187f, 0.0816f, 0.0000f}, {0.1649f, 0.0610f, 0.0000f},
    {0.1212f, 0.0446f, 0.0000f}, {0.0874f, 0.0320f, 0.0000f}, {0.0636f, 0.0232f, 0.0000f},
    {0.0468f, 0.0170f, 0.0000f}, {0.0329f, 0.0119f, 0.0000f}, {0.0227f, 0.0082f, 0.0000f},
    {0.0158f, 0.0057f, 0.0000f}, {0.0114f, 0.0041f, 0.0000f}, {0.0081f, 0.0029f, 0.0000f},
    {0.0058f, 0.0021f, 0.0000f}, {0.0041f, 0.0015f, 0.0000f}, {0.0029f, 0.0010f, 0.0000f},
    {0.0020f, 0.0007f, 0.0000f}, {0.0014f, 0.0005f, 0.0000f}, {0.0010f, 0.0004f, 0.0000f},
    {0.0007f, 0.0002f, 0.0000f}, {0.0005f, 0.0002f, 0.0000f}, {0.0003f, 0.0001f, 0.0000f},
    {0.0002f, 0.0001f, 0.0000f}, {0.0002f, 0.0001f, 0.0000f}, {0.0001f, 0.0000f, 0.0000f},
    {0.0001f, 0.0000f, 0.0000f}, {0.0001f, 0.0000f, 0.0000f}, {0.0000f, 0.0000f, 0.0000f}};

static constant float3 cie_integral_norm_xyz = {0.00935861f, 0.00935843f, 0.00935968f}; // [1/nanometers]
static constant float3 cie_integral_norm_rgb = {0.00776762f, 0.00986860f, 0.01029787f}; // [1/nanometers]

float3 wavelength_to_xyz(float lambda_nm) {
    float ii = (lambda_nm - 380.0f) * (1.0f / 5.0f);
    int i = (int)ii;

    if (i < 0 || i >= 80) return 0;

    return lerp(cie_colour_match[i+0], cie_colour_match[i+1], ii - (float)i);
}
