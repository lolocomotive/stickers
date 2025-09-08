#include <flutter/runtime_effect.glsl>
#include "hsl.frag"

uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uHue;
uniform float uSaturation;

out vec4 fragColor;

void main()
{
    vec2 uv = (FlutterFragCoord().xy-uOffset)/uSize;
    fragColor = vec4(hsl(uHue/360, uSaturation, uv.x), 1.0);
}