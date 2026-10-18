/* WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
1. Paste everything below into your existing chapter file, UNDER what 012 already added.
2. There is no `package` line and no imports here, and NOTHING from 011/012 is repeated (otherwise Odin would complain about names declared twice, like MeshBuffer). This file REUSES these things from 011/012 -
   MeshBuffer, create_textured_vertex_buffer, create_descriptor_pool, create_descriptor_set, shader_stage_info, create_buffer, destroy_buffer, UniformBuffer
   and from the older chapter 3 helpers (same assumed signatures as in the 012 header comment) - create_texture_image, create_image_view, create_texture_sampler, create_depth_resources, create_shader_module,
   create_color_and_depth_render_pass, create_pipeline_layout, create_graphics_pipeline, create_color_and_depth_framebuffers
3. EXTRA ASSUMPTION: VulkanRenderDevice also has u32 fields `framebuffer_width` and `framebuffer_height` (the book's vkDev.framebufferWidth/Height).  */

/* THIS FILE = CHAPTER 4, RECIPES 1 AND 2:
   "Organizing Vulkan frame rendering code" -> RendererBase, VulkanClear, VulkanFinish
   "Organizing mesh rendering in Vulkan" -> ModelRenderer  */

// WHAT WE ARE DOING - 
/* think of one frame as layers, like an image in a graphics editor - 
layer 1 - clear the screen to a background color using VulkanClear 
layer 2 - the 3d model using ModelRenderer
last part - move the image into the ready to present layout using VulkanFinish 

Every layer is an object that owns its own pipeline, render pass, framebuffers, descriptor sets and buffers, and can
record its commands into a command buffer. Then drawing a frame is just - "for each layer, ask it to record commands".

