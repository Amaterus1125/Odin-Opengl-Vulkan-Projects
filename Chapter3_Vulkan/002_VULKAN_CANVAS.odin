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
 5. Per frame - canvas_clear -> canvas_line(...)s -> canvas_update_buffer -> canvas_update_uniform_buffer.  */

// SHARED HELPERS 

/ map a memory block, copy `size` bytes in, unmap (uploadBufferData; used for every per-frame CPU -> GPU copy)
upload_memory :: proc(device : vk.Device , memory: vk.DeviceMemory , offset : vk.DeviceSize , size : int) { 
mapped : rawptr 
vk_check(vk.MapMemory(device , memory , offset , vk.DeviceSize(size) , {} , &mapped)) 
mem.copy(mapped , data , size) 
vk.UnmapMemory(device , memory) 
} 

/* Descriptor sets for layers that read a PER-IMAGE storage buffer (011's create_descriptor_set shares ONE mesh buffer between
all images, so it can't be reused here). Bindings:
0 = uniform buffer   (visible to vertex AND fragment, so it works whichever stage the shader reads it in)
1 = storage buffer   (the vertices)
2 = texture sampler  (fragment) - ONLY added when you pass a sampler. The canvas has no texture, the MicroUI layer (015) does. */

create_geometry_descriptor_set :: proc( 
device: vk.Device, descriptor_pool: vk.DescriptorPool,
uniform_buffers: []vk.Buffer, ubo_size: vk.DeviceSize,
storage_buffers: []vk.Buffer, vertex_range: vk.DeviceSize,
sampler: vk.Sampler, view: vk.ImageView,) -> (layout: vk.DescriptorSetLayout, sets: []vk.DescriptorSet, ok: bool) {
image_count := len(uniform_buffers)
has_texture := sampler != 0

	bindings := make([dynamic]vk.DescriptorSetLayoutBinding)
	defer delete(bindings)
	append(&bindings, descriptor_set_layout_binding(0, .UNIFORM_BUFFER, {.VERTEX, .FRAGMENT}))
	append(&bindings, descriptor_set_layout_binding(1, .STORAGE_BUFFER, {.VERTEX}))
	if has_texture { append(&bindings, descriptor_set_layout_binding(2, .COMBINED_IMAGE_SAMPLER, {.FRAGMENT})) }
layout_info := vk.DescriptorSetLayoutCreateInfo{
sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO, bindingCount = u32(len(bindings)), pBindings = raw_data(bindings),}
	if vk.CreateDescriptorSetLayout(device, &layout_info, nil, &layout) != .SUCCESS { return {}, nil, false }

layouts := make([]vk.DescriptorSetLayout, image_count)
defer delete(layouts)
for i in 0 ..< image_count { layouts[i] = layout }
alloc_info := vk.DescriptorSetAllocateInfo{
sType = .DESCRIPTOR_SET_ALLOCATE_INFO, descriptorPool = descriptor_pool,
descriptorSetCount = u32(image_count), pSetLayouts = raw_data(layouts),
}
sets = make([]vk.DescriptorSet, image_count)
if vk.AllocateDescriptorSets(device, &alloc_info, raw_data(sets)) != .SUCCESS { return layout, sets, false }


