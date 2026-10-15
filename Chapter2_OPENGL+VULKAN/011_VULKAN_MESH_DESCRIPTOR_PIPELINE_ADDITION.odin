// WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
// Paste everything below into your existing 009 or 010 file from chapter 2, UNDER your existing helper procs and ABOVE main. There is no `package` line and no old code repeated here.

/* These older procs must already be in your file (they are called below):
from 008: copy_buffer, UniformBuffer, create_uniform_buffers, update_uniform_buffer
from 009: create_buffer, destroy_buffer, find_memory_type, create_image_view, create_texture_image, create_texture_sampler, find_depth_format 
(008's copy_buffer was NOT copied into 009 if it's missing, copy it over from 013. Don't paste it twice or Odin will complain about a redeclaration.)  */ 

/* Geometry shaders are an optional GPU feature. Wherever main fills in device_features`, turn it on before creating the device: device_features.geometryShader = true  */
/* Compile the 3 new shader files (VK02.vert / VK02.geom / VK02.frag):
glslangValidator -V VK02.vert -o VK02.vert.spv
glslangValidator -V VK02.geom -o VK02.geom.spv
glslangValidator -V VK02.frag -o VK02.frag.spv  */ 

// USING MESH GEOMETRY DATA IN VULKAN  
/* Same programmable vertex pulling (PVP) idea as our OpenGL 008 file: no vertex attributes. The shader gets the raw vertices AND the raw indices as storage buffers (SSBOs) and looks things up itself, we use cgltf, exactly as in 008. */

//must match "struct VertexData" in VK02 vert: 5 plain floats , 20 bytes 
VertexData :: struct { 
pos : [3]f32 , 
tc : [2]f32 , } 

