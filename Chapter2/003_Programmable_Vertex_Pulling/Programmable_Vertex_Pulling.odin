//THE NORMAL IMPORTS FOR EVERY FILE 

package main

import "core:fmt"
import "core:math/linalg"

import "vendor:glfw"
import gl "vendor:OpenGL"
import cgltf "vendor:cgltf"
import stbi "vendor:stb/image"

// PROGRAMMABLE VERTEX PULLING - 
/* 
Normally opengl feeds vertex data to our shader sutomatically , we set up VAO that says "position is 3 floats starting here, uv is 2 floats starting here" and the GPU hands your shader the right numbers for each vertex without us doing anything,

PVP throws that automatic part away and instead we hand the shader a big raw buffer of number directly as an SSBO - shader storage buffer object, ssbo is just a big array that shader can read from manually, and let the shader look up whatever it needs itself,
using gl_VertexID (a vertex no. which gpu provides to a vertex itself) as an index into that array 

Doing indexing by hand helps us later on to cram multiple different meshes into one giant buffer and drawing them all on a single draw call, without opengl needing to stop and switch buffers/ VAO between each mesh, fewer draw calls will also help in 
CPU spending less time telling the GPU to draw something, this is just step 1 where we manually indexing a single mesh so to see how the mechanism works before combining multiple meshes later  */

PerFrameData :: struct { 
 mvp : matrix[4,4]f32,
}

// this has to exactly match the shader's "Vertex" struct below, including using separate floats instead of a vec3
VertexData:struct { 
 pos:[3]f32,
 tc : [3]f32,
}

vertex_src := `#version 460 core 
layout(std140 , binding = 0) uniform PerFramData { 
 uniform mat4 MVP;
};

/* this struct layout must match the VertexData on the odin side exactly , we use float[3] / float[2] instead of vec3/ vec2 here on purpose,as GLSL silently pads a vec3 to take up same space as a vec4 (16 bytes) instead a buffer like this ,
which would make our odin struct and the shader struct diagree about where each vertex data actually start, plain floats have no such padding , so both sides agree */

struct Vertex { float p[3] ; float tc[2]; };

//binding = 1 here is our raw vertex data buffer, readonly just means that the shader can only read from it and never write back to it 

layout(std430, binding = 1) readonly buffer Vertices { Vertex in_Vertices[]; };

vec3 getPosition(int i) { return vec3(in_Vertices[i].p[0], in_Vertices[i].p[1], in_Vertices[i].p[2]); }
vec2 getTexCoord(int i) { return vec2(in_Vertices[i].tc[0], in_Vertices[i].tc[1]); }

layout (loaction =0) out vec2 uv;
void main() { 
// gl_VertexID normally just counts 0 ,1,2,3 but since our VAO has an index buffer attached , opengl automatically feels gl_VertexID the actual index values insread , so this naturally puls the right vertex , reused across shared corners , same as normal indexed rendering would 
vec3 pos = getPosition(gl_VertexID);
gl_position = MVP * vec4(pos, 1.0) ;
uv = getTexCoord(gl_VertexID) ;
}`

fragment_src := `#version 460 core 
layout(location =0) in vec2 uv;
layout(location =0) out vec4 out_FragColor;
layout(location =0) uniform sampler2D texture0;
void main() { 
  out_FragColor = texture(texture0 , uv);
}`








