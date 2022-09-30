#pragma once

float luminance(float3 color) {
    // ITU-R standard
    return dot(float3(0.2126, 0.7152, 0.0722), color);
}

// adapted from blender/intern/cycles/util/color.h
float3 rgb2hsv(float3 rgb) {
  float cmax, cmin, h, s, v, cdelta;
  float3 c;

  cmax = max(rgb.x, max(rgb.y, rgb.z));
  cmin = min(rgb.x, min(rgb.y, rgb.z));
  cdelta = cmax - cmin;

  v = cmax;

  if (cmax != 0.0f) {
    s = cdelta / cmax;
  } else {
    s = 0.0f;
    h = 0.0f;
  }

  if (s != 0.0f) {
    c = (cmax - rgb) / cdelta;

    if (rgb.x == cmax)
      h = c.z - c.y;
    else if (rgb.y == cmax)
      h = 2.0f + c.x - c.z;
    else
      h = 4.0f + c.y - c.x;

    h /= 6.0f;

    if (h < 0.0f)
      h += 1.0f;
  } else {
    h = 0.0f;
  }

  return float3(h, s, v);
}

// adapted from blender/intern/cycles/util/color.h
float3 hsv2rgb(float3 hsv) {
  float i, f, p, q, t, h, s, v;
  float3 rgb;

  h = hsv.x;
  s = hsv.y;
  v = hsv.z;

  if (s != 0.0f) {
    if (h == 1.0f)
      h = 0.0f;

    h *= 6.0f;
    i = floor(h);
    f = h - i;
    rgb = f;
    p = v * (1.0f - s);
    q = v * (1.0f - (s * f));
    t = v * (1.0f - (s * (1.0f - f)));

    if (i == 0.0f)
      rgb = float3(v, t, p);
    else if (i == 1.0f)
      rgb = float3(q, v, p);
    else if (i == 2.0f)
      rgb = float3(p, v, t);
    else if (i == 3.0f)
      rgb = float3(p, q, v);
    else if (i == 4.0f)
      rgb = float3(t, p, v);
    else
      rgb = float3(v, p, q);
  } else {
    rgb = float3(v, v, v);
  }

  return rgb;
}

float3 xyz_to_rgb(float x, float y, float z) {
    return float3(3.240479 * x + -1.537150 * y + -0.498535 * z,
                 -0.969256 * x + 1.875991 * y + 0.041556 * z,
                  0.055648 * x + -0.204043 * y + 1.057311 * z);
}

float3 xyY_to_xyz(float x, float y, float Y) {
    float X, Z;

    if (y != 0.0f)
        X = (x / y) * Y;
    else
        X = 0.0f;

    if (y != 0.0f && Y != 0.0f)
        Z = (1.0f - x - y) / y * Y;
    else
        Z = 0.0f;

    return float3(X, Y, Z);
}
