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

for i in 0 ..< image_count {
ubo_info := vk.DescriptorBufferInfo{buffer = uniform_buffers[i], offset = 0, range = ubo_size}
vertices_info := vk.DescriptorBufferInfo{buffer = storage_buffers[i], offset = 0, range = vertex_range}
image_info := vk.DescriptorImageInfo{sampler = sampler, imageView = view, imageLayout = .SHADER_READ_ONLY_OPTIMAL}

writes := make([dynamic]vk.WriteDescriptorSet)
defer delete(writes)
append(&writes, vk.WriteDescriptorSet{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER, pBufferInfo = &ubo_info})
append(&writes, vk.WriteDescriptorSet{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 1, descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &vertices_info})
if has_texture {
append(&writes, vk.WriteDescriptorSet{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 2, descriptorCount = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, pImageInfo = &image_info})
}
vk.UpdateDescriptorSets(device, u32(len(writes)), raw_data(writes), 0, nil)
}
return layout, sets, true
}

// pipeline layout + vertex/fragment shaders + pipeline , stored in base , (pipeline creation boilerplate and both new layes need the same steps so it lives here once) 
renderer_create_pipeline :: proc( 
self : ^RendererBase , vk_dev : ^VUlkanRenderDevice , vert_file , frag_file : string , topology : vk.PrimitiveTopology , use_depth , use_blending , dynamic_scissor : bool ,) -> bool{ 
ok : bool 
self.pipeline_layout, ok = create_pipeline_layout(vk_dev.device, self.descriptor_set_layout)
	if !ok { return false }
vert_module, frag_module: vk.ShaderModule
vert_module, ok = create_shader_module(vk_dev.device, vert_file)
if !ok { return false }
frag_module, ok = create_shader_module(vk_dev.device, frag_file)
if !ok { return false }

stages := [2]vk.PipelineShaderStageCreateInfo{
shader_stage_info({.VERTEX},   vert_module, "main"),
shader_stage_info({.FRAGMENT}, frag_module, "main"),
}
self.graphics_pipeline, ok = create_graphics_pipeline(
vk_dev.device, self.framebuffer_width, self.framebuffer_height, self.render_pass, self.pipeline_layout, stages[:], topology, use_depth, use_blending, dynamic_scissor,
)
vk.DestroyShaderModule(vk_dev.device, vert_module, nil) // the pipeline keeps its own copy
vk.DestroyShaderModule(vk_dev.device, frag_module, nil)
return ok
}

// PART 2 - VulkanCanvas - immediate-mode debug lines 

//one canvas vertex = 3D position + color = 7 floats = 28 bytes , the canvas must read it as plain floats 
CanvasVertex :: struct { 
position : [3]f32, 
color : [4]f32 ,
}

//per frame uniform data , the combined model view projection matrix and the current time 
CanvasUniform :: struct { 
mvp : matrix[4,4]f32 , 
time : f32 , 
} 

// the GPU buffer is pre-allocated for a fixed maximum, so we can never draw more than this many lines
CANVAS_MAX_LINES_COUNT :: 65536
CANVAS_MAX_LINES_DATA_SIZE :: 2 * CANVAS_MAX_LINES_COUNT * size_of(CanvasVertex) // 2 vertices per line

VulkanCanvas :: struct { 
using renderer : Renderer , //keeping first always
lines : [dynamic]CanvasVertex . //cpu side list , 2 vertices per line 
storage_buffers : []vk.Buffer , //gpu copy of the list , one per swapchain image as always 
storage_buffers_memory : []vk.DeviceMemory , 
} 

// 'depth' is the shared depth buffer (model.depth_texture) , so lines hide behind the duck correctly 
canvas_init :: proc(self: ^VulkanCanvas , vk_dev : ^VulkanRenderDevice , depth: VulkanImage , vert_file , frag_file: string) -> bool { 
renderer_base_init(&self.base, vk_dev, depth)
self.fill_command_buffer = canvas_fill_command_buffer
self.destroy = canvas_destroy
ok: bool
image_count := len(vk_dev.swapchain_images)

//one geometry buffer per swapchain image , CPU writable 
self.storage_buffers        = make([]vk.Buffer, image_count)
self.storage_buffers_memory = make([]vk.DeviceMemory, image_count)
for i in 0 ..< image_count {
	self.storage_buffers[i], self.storage_buffers_memory[i], ok = create_buffer(
	vk_dev.device, vk_dev.physical_device, CANVAS_MAX_LINES_DATA_SIZE,
	{.STORAGE_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
)
if !ok {
fmt.println("VulkanCanvas: create_buffer() failed")
	return false
 }
}

if !renderer_create_uniform_buffers(&self.base, vk_dev, size_of(CanvasUniform)) { return false }

// pool counts per image , 1 uniform , 1 storage , 0 samplers(no texture , no index buffers) 
self.descriptor_pool, ok = create_descriptor_pool(vk_dev.device, u32(image_count), 1, 1, 0)
if !ok { return false }
self.descriptor_set_layout, self.descriptor_sets, ok = create_geometry_descriptor_set(
vk_dev.device, self.descriptor_pool, self.uniform_buffers, size_of(CanvasUniform),
self.storage_buffers, CANVAS_MAX_LINES_DATA_SIZE, 0, 0, // sampler 0 = no texture binding
)
if !ok { return false }

// middle layer; uses the shared depth buffer
self.render_pass, ok = create_color_and_depth_render_pass(vk_dev.device, true, RenderPassCreateInfo{})
if !ok { return false }

// LINE_LIST so every 2 vertices become one line; depth test on; blending on , depth test is one of the many test we can do 
if !renderer_create_pipeline(&self.base, vk_dev, vert_file, frag_file, .LINE_LIST, true, true, false) { return false }
self.swapchain_framebuffers, ok = create_color_and_depth_framebuffers(vk_dev, self.render_pass, depth.view, self.framebuffer_width, self.framebuffer_height)
return ok
}

// THE NON VULKAN PART - BUILD UP THE LIST OF LINES - 

canvas_clear :: proc(self : ^VulkanCanvas) { 
clear(self.lines) 
} 

//add 2 points to the list , safety - ignores the line once the pre allocated gpu buffer would overflow bc it can only hold a max fixed amt of lines 

canvas_line :: proc(self: ^VulkanCanvas , p1 , p2 : [3]f32 , color : [4]f32 ) { 
if len(self.lines) + 2 > 2 * CANVAS_MAX_LINES_COUNT {return} 
append(&self.lines, CanvasVertex{position = p1, color = color})
append(&self.lines, CanvasVertex{position = p2, color = color})
}

