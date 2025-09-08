#include <flutter/runtime_effect.glsl>
#include "hsl.frag"

uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uSaturation;
uniform float uLightness;

out vec4 fragColor;

void main()
{
    vec2 uv = (FlutterFragCoord().xy-uOffset)/uSize;
    fragColor = vec4(hsl(uv.x, uSaturation, uLightness), 1.0);
}