// ADDITIONS ONLY FILE - paste under 002 chapter 3 in your combined file. No package line, nothing from previous repeated.
// This replaces the CPP Dear ImGui renderer with a MicroUI renderer, built as a REUSABLE layer.
// MicroUI ships with Odin (vendor:microui), so no extra dependency.

/* WHERE THE NEW CODE IS - 
 [MUI-1] MuiRenderer  - The reusable UI layer. One struct, init / update / fill_command_buffer / destroy.It knows NOTHING about your specific UI: you give it a "ui_proc" and it draws whatever that builds.
 [MUI-2] Input - mui_poll_glfw_input: feeds mouse position and buttons from GLFW into MicroUI.
 [MUI-3] Batching - Mui_update + mui_push_quad: turns MicroUI's commands (rect / text / icon / clip) into triangles and a list of draw calls (a new draw call whenever MicroUI changes the clip rectangle).
 [MUI-4] Shaders - The two small GLSL shaders for this layer are in a comment at the bottom (the book has none for MicroUI).
*/ 

/*  NOT REPEATED HERE (already in 011-014): Renderer / RendererBase / renderer_* helpers, VulkanImage, upload_memory,
 create_geometry_descriptor_set (014, with its optional texture binding), renderer_create_pipeline (014), create_buffer,
 create_descriptor_pool, vk_check, the clear / model / canvas / finish layers.

 /* 
IMPORTS (at the top of your file):   import mu "vendor:microui"
ASSUMPTIONS (same style as before):
a) create_graphics_pipeline has the optional params from 014 (topology, use_depth, use_blending, dynamic_scissor).
b) create_color_and_depth_framebuffers accepts depth_view = 0 (no depth buffer on this layer).
c) create_texture_image_from_data(device, physical_device, command_pool, queue, pixels: rawptr, width, height: i32,format: vk.Format, ^vk.Image, ^vk.DeviceMemory) -> bool    
d) The pipeline must NOT cull our triangles (cull mode NONE). If you see nothing on screen, check this first.
e) MicroUI names used: mu.default_atlas_alpha, mu.default_atlas, mu.DEFAULT_ATLAS_WIDTH / HEIGHT / WHITE / FONT If one is named differently in your Odin version, only [MUI-1] and [MUI-3] need touching.
*/ 
