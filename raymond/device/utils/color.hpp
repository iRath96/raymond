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
