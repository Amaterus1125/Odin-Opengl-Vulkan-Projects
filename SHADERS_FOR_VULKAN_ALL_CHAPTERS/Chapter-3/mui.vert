#version 460

struct Vertex { float x, y, u, v; uint color; };   

layout(binding = 0) uniform UniformBuffer { mat4 proj; } ubo;
layout(std430, binding = 1) readonly buffer Vertices { Vertex in_Vertices[]; };

layout(location = 0) out vec2 uv;
layout(location = 1) out vec4 color;

void main() {
    Vertex v = in_Vertices[gl_VertexIndex];        
    gl_Position = ubo.proj * vec4(v.x, v.y, 0.0, 1.0);
    uv = vec2(v.u, v.v);
    color = unpackUnorm4x8(v.color);              
}
