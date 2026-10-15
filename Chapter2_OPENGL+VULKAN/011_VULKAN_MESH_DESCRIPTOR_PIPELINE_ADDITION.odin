// WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
// Paste everything below into your existing 009 or 010 file from chapter 2, UNDER your existing helper procs and ABOVE main. There is no `package` line and no old code repeated here.

/* These older procs must already be in your file (they are called below):
from 008: copy_buffer, UniformBuffer, create_uniform_buffers, update_uniform_buffer
from 009: create_buffer, destroy_buffer, find_memory_type, create_image_view, create_texture_image, create_texture_sampler, find_depth_format 
(008's copy_buffer was NOT copied into 009 if it's missing, copy it over from 013. Don't paste it twice or Odin will complain about a redeclaration.)  */ 


/* WHAT THIS FILE DOES - same as before using duck model from rubber_duck and the scene.gltf thing 
1. Loads the duck mesh from scene.gltf and uploads its vertices AND indices into ONE GPU buffer (a "storage buffer", SSBO).
2. Creates a descriptor pool, a descriptor set layout, and one descriptor set per swapchain image. A descriptor set is the list of resources (uniform buffer, vertex buffer, index buffer, texture)
the shaders are allowed to use. Vulkan won't let a shader use a buffer or texture any other way.  */

// USING MESH GEOMETRY DATA IN VULKAN  
/* Same programmable vertex pulling (PVP) idea as our OpenGL 008 file: no vertex attributes. The shader gets the raw vertices AND the raw indices as storage buffers (SSBOs) and looks things up itself, we use cgltf, exactly as in 008. */

//must match "struct VertexData" in VK02 vert: 5 plain floats , 20 bytes 
VertexData :: struct { 
pos : [3]f32 , 
tc : [2]f32 , } 

/* everything we need to remmeber about the uploaded mesh , we returns these through seperate out pointers (storageBuffer , vertexBufferSize 
, indexBufferSize) , but in odin we just make one struct hehe */ 
MeshBuffer :: struct { 
buffer : vk.Buffer,  //one buffer holding vertices first and then indices 
memory: vk.DeviceMemory , 
vertex_size : vk.DeviceSize  // size of the vertex section in bytes 
index_offset: vk.DeviceSize, // where the index section starts inside the buffer 
vertex_offset : vk.DeviceSize // size of the index section in bytes 
} 

/* Vulkan only lets a storage buffer descriptor start at an offset that's a multiple of the GPU minStorageOffsetAlignment (anywhere from 4 to 256 depending on GPU) , 256 is 
the largest value in common use , so we pad up to it and some problems won't happen */ 

STORAGE_OFFSET_ALIGNMENT :: 256 


