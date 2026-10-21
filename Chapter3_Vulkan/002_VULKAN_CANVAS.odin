/* ADDITIONS ONLY - paste under 001 in chapter 3 in your combined file. No package line, nothing from chapter 2 repeated.
what we doing - "Implementing an immediate mode drawing canvas", the Dear ImGui renderer, is done with MicroUI instead - in next file 003_MICROUI_RENDERER */
 
/* NEW THINGS WE ADDED - 
1. upload_memory, create_geometry_descriptor_set, renderer_create_pipeline, Small shared helpers. VulkanCanvas uses them, and so does the MicroUI layer in 003.
2. VulkanCanvas - Debug line drawing. You call canvas_line() / canvas_plane3d() every frame, it draws them in ONE draw call.(this is what you use for bounding boxes, grids, debug lines)
*/ 

//NOT REPEATED HERE - NOT REPEATED HERE (already in 011-013): Renderer / RendererBase and the renderer_* helpers, VulkanImage, VulkanClear/Finish, ModelRenderer, create_buffer / destroy_buffer, create_descriptor_pool, shader_stage_info, vk_check, and the older chapter 3 helpers.

/* NEW ASSUMPTION - 
  create_graphics_pipeline takes 4 extra OPTIONAL params, as in the book:
  topology := vk.PrimitiveTopology.TRIANGLE_LIST, use_depth := true, use_blending := false, dynamic_scissor := false
  The canvas needs LINE_LIST (and blending). 003 needs blending + dynamic scissor. If yours doesn't have them, add them. */

/*SHADERS YOU NEED: a canvas vert+frag pair */

/*  THE THINGS TO REMEMBER FROM PREVIOUS FILES AND PROJETS 
 1. Vulkan has no "draw a line now" call. So: keep a CPU list of vertices, copy it into a GPU storage buffer every frame, then draw with vertex pulling (no vertex buffer, the shader reads the storage buffer). Same trick as the duck.
 2. ONE storage buffer PER swapchain image, so the CPU never overwrites data the GPU is still reading (no sync needed).
 3. Canvas draw count = number of vertices (2 per line), all in one vk.CmdDraw. No lines = no render pass at all.
 4. It's a MIDDLE layer (render pass flags = {}). Layer order for the full app - clear -> model -> canvas -> ui (015) -> finish
 5. Per frame - canvas_clear -> canvas_line(...)s -> canvas_update_buffer -> canvas_update_uniform_buffer.       */

