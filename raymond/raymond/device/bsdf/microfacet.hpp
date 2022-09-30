#pragma once

/**
 * Evaluates the isotropic GTR1 normal distribution function.
 * @see "Diffuse Reflection of Light from a Matt Surface" [Berry 1923]
 * @see "Physically Based Shading at Disney" [Burley 2012]
 */
float gtr1(float3 wh, float a) {
    float nDotH = ShadingFrame::cosTheta(wh);
    float a2 = square(a);
    float t = 1 + (a2 - 1) * square(nDotH);
    return (a2 - 1) / (M_PI_F * log(a2) * t);
}

/**
 * Samples the isotropic GTR1 normal distribution function.
 * @return A microfacet normal that will always lie in the upper hemisphere.
 * @note The PDF of @c wh is given by:
 *   @code cosTheta(wh) * D(wh) @endcode
 */
float3 sampleGTR1(float2 rnd, float a) {
    float a2 = square(a);

    float cosTheta = safe_sqrt((1 - pow(a2, 1 - rnd.x)) / (1 - a2));
    float sinTheta = safe_sqrt(1 - (cosTheta * cosTheta));
    float phi = 2 * M_PI_F * rnd.y;
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

/**
 * Isotropic Smith shadowing/masking function for the GGX microfacet distribution.
 * This function also ensures that the orientation of @c w matches the orientation of @c wh and returns @c 0 if that is not the case.
 * @note This is used for the clearcoat lobe, even though it is not a physically correct match for its GTR1 NDF.
 *       While better matches became available after the original Disney BRDF publication, they seemingly liked the look of this function more.
 */
float smithG1(float3 w, float3 wh, float a) {
    /// Ensure correct orientation by projecting both @c w and @c wh into the upper hemisphere and checking that the angle they form is less than 90°
    if (dot(w, wh) * ShadingFrame::cosTheta(w) * ShadingFrame::cosTheta(wh) <= 0) return 0;
    
    /// Special case: if @c cosTheta of @c w is large, we know that the tangens will be @c 0 and hence our result is @c 1
    if (abs(ShadingFrame::cosTheta(w)) >= 1) return 1;
    
    const float a2tanTheta2 = square(a) * ShadingFrame::tanTheta2(w);
    return 2 / (1 + sqrt(1 + a2tanTheta2));
}

/**
 * Anisotropic Smith shadowing/masking function for the GGX microfacet distribution.
 * This function also ensures that the orientation of @c w matches the orientation of @c wh and returns @c 0 if that is not the case.
 * @note This is used for the specular lobes of the Disney BSDF.
 */
float anisotropicSmithG1(float3 w, float3 wh, float ax, float ay) {
    /// Ensure correct orientation by projecting both @c w and @c wh into the upper hemisphere and checking that the angle they form is less than 90°
    if (dot(w, wh) * ShadingFrame::cosTheta(w) * ShadingFrame::cosTheta(wh) <= 0) return 0;
    
    /// Special case: if @c cosTheta of @c w is large, we know that the tangent will be @c 0 and hence our result is @c 1
    if (abs(ShadingFrame::cosTheta(w)) >= 1) return 1;
    
    const float a2tanTheta2 = (
        square(ax * ShadingFrame::cosPhiSinTheta(w)) +
        square(ay * ShadingFrame::sinPhiSinTheta(w))
    ) / ShadingFrame::cosTheta2(w);
    return 2 / (1 + sqrt(1 + a2tanTheta2));
}

/**
 * Evaluates the anisotropic GGX normal distribution function.
 * @see "Microfacet Models for Refraction through Rough Surfaces" [Walter et al. 2007]
 */
float anisotropicGGX(float3 wh, float ax, float ay) {
    float nDotH = ShadingFrame::cosTheta(wh);
    float a = ShadingFrame::cosPhiSinTheta(wh) / ax;
    float b = ShadingFrame::sinPhiSinTheta(wh) / ay;
    float c = square(a) + square(b) + square(nDotH);
    return 1 / (M_PI_F * ax * ay * square(c));
}

/**
 * Sampling of the visible normal distribution function (VNDF) of the GGX microfacet distribution with Smith shadowing function by [Heitz 2018].
 * @note The PDF of @c wh is given by:
 *   @code G1(wo) * max(0, dot(wo, wh)) * D(wh) / cosTheta(wo) @endcode
 * @see For details on how and why this works, check out Eric Heitz' great JCGT paper "Sampling the GGX Distribution of Visible Normals".
 */
float3 sampleGGXVNDF(float2 rnd, float ax, float ay, float3 wo) {
    // Addition: flip sign of incident vector for transmission
    float sgn = sign(ShadingFrame::cosTheta(wo));
	// Section 3.2: transforming the view direction to the hemisphere configuration
	float3 Vh = sgn * normalize(float3(ax * wo.x, ay * wo.y, wo.z));
	// Section 4.1: orthonormal basis (with special case if cross product is zero)
	float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
	float3 T1 = lensq > 0 ? float3(-Vh.y, Vh.x, 0) * rsqrt(lensq) : float3(1,0,0);
	float3 T2 = cross(Vh, T1);
	// Section 4.2: parameterization of the projected area
	float r = sqrt(rnd.x);
	float phi = 2.0 * M_PI_F * rnd.y;
	float t1 = r * cos(phi);
	float t2 = r * sin(phi);
	float s = 0.5 * (1.0 + Vh.z);
	t2 = (1.0 - s)*sqrt(1.0 - t1*t1) + s*t2;
	// Section 4.3: reprojection onto hemisphere
	float3 Nh = t1*T1 + t2*T2 + sqrt(max(0.0, 1.0 - t1*t1 - t2*t2))*Vh;
	// Section 3.4: transforming the normal back to the ellipsoid configuration
	float3 Ne = normalize(float3(ax * Nh.x, ay * Nh.y, max(0.f, Nh.z)));
	return sgn * Ne;
}
