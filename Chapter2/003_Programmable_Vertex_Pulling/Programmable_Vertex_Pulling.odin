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


