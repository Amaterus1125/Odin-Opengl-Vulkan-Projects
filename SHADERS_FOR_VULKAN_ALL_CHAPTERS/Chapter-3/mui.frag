#version 460

layout(binding = 2) uniform sampler2D atlas;

layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = color * texture(atlas, uv);         
}
