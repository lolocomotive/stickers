// Adapted from https://gist.github.com/mjackson/5311256
float hueToRgb(float p, float q, float t) {
    t = fract(t);

    float c1 = step(1.0/6.0, t);
    float c2 = step(1.0/2.0, t);
    float c3 = step(2.0/3.0, t);

    float term1 = mix(p + (q - p) * 6.0 * t, q, c1);
    float term2 = mix(term1, p + (q - p) * (2.0/3.0 - t) * 6.0, c2);
    float final = mix(term2, p, c3);

    return final;
}

vec3 hsl(float h, float s, float l) {
    vec3 grayscale = vec3(l);

    float q = mix(l * (1.0 + s), l + s - l * s, step(0.5, l));
    float p = 2.0 * l - q;

    float r = hueToRgb(p, q, h + 1.0/3.0);
    float g = hueToRgb(p, q, h);
    float b = hueToRgb(p, q, h - 1.0/3.0);
    vec3 color = vec3(r, g, b);

    return mix(grayscale, color, step(0.0001, s));
}