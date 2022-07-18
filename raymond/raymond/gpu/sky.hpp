#pragma once

// taken from blender/intern/cycles/kernel/osl/shaders/node_sky_texture.osl

//#include "node_color.h"
//#include "stdcycles.h"

float sky_angle_between(float thetav, float phiv, float theta, float phi) {
    float cospsi = sin(thetav) * sin(theta) * cos(phi - phiv) + cos(thetav) * cos(theta);

    if (cospsi > 1.0)
        return 0.0;
    if (cospsi < -1.0)
        return M_PI_F;

    return acos(cospsi);
}

float2 sky_spherical_coordinates(float3 dir) {
    return float2(acos(dir.z), atan2(dir.x, dir.y));
}

/* Preetham */
float sky_perez_function(float lam[9], float theta, float gamma) {
    float ctheta = cos(theta);
    float cgamma = cos(gamma);

    return (1.0 + lam[0] * exp(lam[1] / ctheta)) *
           (1.0 + lam[2] * exp(lam[3] * gamma) + lam[4] * cgamma * cgamma);
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

float3 xyz_to_rgb(float x, float y, float z) {
    return float3(3.240479 * x + -1.537150 * y + -0.498535 * z,
                 -0.969256 * x + 1.875991 * y + 0.041556 * z,
                  0.055648 * x + -0.204043 * y + 1.057311 * z);
}

float3 sky_radiance_preetham(
    float3 dir,
    float sunphi,
    float suntheta,
    float3 radiance,
    float config_x[9],
    float config_y[9],
    float config_z[9]
) {
    /* convert vector to spherical coordinates */
    float2 spherical = sky_spherical_coordinates(dir);
    float theta = spherical.x;
    float phi = spherical.y;

    /* angle between sun direction and dir */
    float gamma = sky_angle_between(theta, phi, suntheta, sunphi);

    /* clamp theta to horizon */
    theta = min(theta, M_PI_2_F - 0.001f);

    /* compute xyY color space values */
    float x = radiance.y * sky_perez_function(config_y, theta, gamma);
    float y = radiance.z * sky_perez_function(config_z, theta, gamma);
    float Y = radiance.x * sky_perez_function(config_x, theta, gamma);

    /* convert to RGB */
    float3 xyz = xyY_to_xyz(x, y, Y);
    return xyz_to_rgb(xyz.x, xyz.y, xyz.z);
}

/* Hosek / Wilkie */
float sky_radiance_internal(float config[9], float theta, float gamma) {
    float ctheta = cos(theta);
    float cgamma = cos(gamma);

    float expM = exp(config[4] * gamma);
    float rayM = cgamma * cgamma;
    float mieM = (1.0 + rayM) / pow((1.0 + config[8] * config[8] - 2.0 * config[8] * cgamma), 1.5);
    float zenith = sqrt(ctheta);

    return (1.0 + config[0] * exp(config[1] / (ctheta + 0.01))) *
           (config[2] + config[3] * expM + config[5] * rayM + config[6] * mieM + config[7] * zenith);
}

float3 sky_radiance_hosek(
    float3 dir,
    float sunphi,
    float suntheta,
    float3 radiance,
    float config_x[9],
    float config_y[9],
    float config_z[9]
) {
    /* convert vector to spherical coordinates */
    float2 spherical = sky_spherical_coordinates(dir);
    float theta = spherical.x;
    float phi = spherical.y;

    /* angle between sun direction and dir */
    float gamma = sky_angle_between(theta, phi, suntheta, sunphi);

    /* clamp theta to horizon */
    theta = min(theta, M_PI_2_F - 0.001f);

    /* compute xyz color space values */
    float x = sky_radiance_internal(config_x, theta, gamma) * radiance.x;
    float y = sky_radiance_internal(config_y, theta, gamma) * radiance.y;
    float z = sky_radiance_internal(config_z, theta, gamma) * radiance.z;

    /* convert to RGB and adjust strength */
    return xyz_to_rgb(x, y, z) * (2 * M_PI_F / 683);
}

/* Nishita improved */
float3 geographical_to_direction(float lat, float lon) {
    return float3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat));
}

float precise_angle(float3 a, float3 b) {
    return 2.f * atan2(length(a - b), length(a + b));
}

float3 sky_radiance_nishita(float3 dir, float nishita_data[10], texture2d<float> texture) {
  /* definitions */
  float sun_elevation = nishita_data[6];
  float sun_rotation = nishita_data[7];
  float angular_diameter = nishita_data[8];
  float sun_intensity = nishita_data[9];
  int sun_disc = angular_diameter > 0;
  float3 xyz = float3(0, 0, 0);
  /* convert dir to spherical coordinates */
  float2 direction = sky_spherical_coordinates(dir);

  /* render above the horizon */
  if (dir.z >= 0.0) {
    /* definitions */
    float3 sun_dir = geographical_to_direction(sun_elevation, sun_rotation + M_PI_2_F);
    float sun_dir_angle = precise_angle(dir, sun_dir);
    float half_angular = angular_diameter / 2.0;
    float dir_elevation = M_PI_2_F - direction.x;

    /* if ray inside sun disc render it, otherwise render sky */
    if (sun_dir_angle < half_angular && sun_disc == 1) {
      /* get 2 pixels data */
      float3 pixel_bottom = float3(nishita_data[0], nishita_data[1], nishita_data[2]);
      float3 pixel_top = float3(nishita_data[3], nishita_data[4], nishita_data[5]);
      float y;

      /* sun interpolation */
      if (sun_elevation - half_angular > 0.0) {
        if ((sun_elevation + half_angular) > 0.0) {
          y = ((dir_elevation - sun_elevation) / angular_diameter) + 0.5;
          xyz = mix(pixel_bottom, pixel_top, y) * sun_intensity;
        }
      }
      else {
        if (sun_elevation + half_angular > 0.0) {
          y = dir_elevation / (sun_elevation + half_angular);
          xyz = mix(pixel_bottom, pixel_top, y) * sun_intensity;
        }
      }
      /* limb darkening, coefficient is 0.6f */
      float angle_fraction = sun_dir_angle / half_angular;
      float limb_darkening = (1.0 - 0.6 * (1.0 - sqrt(1.0 - angle_fraction * angle_fraction)));
      xyz *= limb_darkening;
    }
    /* sky */
    else {
      /* sky interpolation */
      float x = (direction.y + M_PI_F + sun_rotation) / (2 * M_PI_F);
      /* more pixels toward horizon compensation */
      float y = sqrt(dir_elevation / M_PI_2_F);
      if (x > 1.0) {
        x = x - 1.0;
      }
      constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
      xyz = texture.sample(linearSampler, float2(x, y)).xyz;
    }
  }
  /* ground */
  else {
    if (dir.z < -0.4) {
      xyz = float3(0, 0, 0);
    }
    else {
      /* black ground fade */
      float mul = pow(1.0 + dir.z * 2.5, 3.0);
      /* interpolation */
      float x = (direction.y + M_PI_F + sun_rotation) / (2 * M_PI_F);
      float y = 1e-3; /// @todo this seems fishy
      if (x > 1.0) {
        x = x - 1.0;
      }
      constexpr sampler linearSampler(address::repeat, coord::normalized, filter::linear);
      xyz = texture.sample(linearSampler, float2(x, y)).xyz * mul;
    }
  }
  /* convert to RGB */
  return xyz_to_rgb(xyz.x, xyz.y, xyz.z);
}
