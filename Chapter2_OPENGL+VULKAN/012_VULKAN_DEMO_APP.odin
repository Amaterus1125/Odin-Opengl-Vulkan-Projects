// WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
// Paste everything below into your existing file from chapter 3, UNDER your existing helper procs.
// There is no `package` line here. If you already have a `main` proc, REPLACE it with the one at the bottom of this file.

// THIS FILE TAKES 011 (MESH BUFFER + DESCRIPTOR SETS) AND COMBINES IT WITH THE "VK02 DEMO APP" RECIPE (rendering the rubber duck).
// PART 1 + PART 2 = the code from 011 
// PART 3 = the NEW for thee demo app, state structs, init_vulkan, fill_command_buffer, draw_overlay, terminate_vulkan, main.

/* IMPORTS - Odin imports can't be pasted in the middle of a file, so make sure these are at the TOP of your file:
	import "core:fmt"
	import "core:mem"
	import "core:os"
	import "core:math/linalg"
	import "vendor:glfw"
	import vk "vendor:vulkan"
	import cgltf "vendor:cgltf"
*/

/* PROCS FROM OLDER FILES THAT THIS FILE CALLS (they must already exist in your file).
I don't have your older files, so the signatures below are my ASSUMPTION and if yours look different, only the call sites inside init_vulkan() need changing.

from 008-010 (already used by 011):  create_buffer, destroy_buffer, copy_buffer, UniformBuffer { mvp: matrix[4,4]f32 }
from chapter 3 initialisation recipes:
	create_instance() -> (vk.Instance, bool)
	setup_debug_callbacks(instance) -> (vk.DebugUtilsMessengerEXT, bool)
	init_vulkan_render_device(^VulkanRenderDevice, instance, surface, width, height, features: vk.PhysicalDeviceFeatures) -> bool
	destroy_vulkan_render_device(^VulkanRenderDevice)
	create_shader_module(device, filename: string) -> (vk.ShaderModule, bool)
	create_texture_image(device, physical_device, command_pool, queue, filename: string, ^vk.Image, ^vk.DeviceMemory) -> bool
	create_image_view(device, image, format, aspect: vk.ImageAspectFlags) -> (vk.ImageView, bool)
	create_texture_sampler(device) -> (vk.Sampler, bool)
	create_depth_resources(^VulkanRenderDevice, width, height) -> (vk.Image, vk.DeviceMemory, vk.ImageView, bool)
	create_color_and_depth_render_pass(device, use_depth: bool, info: RenderPassCreateInfo) -> (vk.RenderPass, bool)
	create_pipeline_layout(device, set_layout) -> (vk.PipelineLayout, bool)
	create_graphics_pipeline(device, width, height, render_pass, pipeline_layout, stages: []vk.PipelineShaderStageCreateInfo) -> (vk.Pipeline, bool)
	create_color_and_depth_framebuffers(^VulkanRenderDevice, render_pass, depth_view, width, height) -> ([]vk.Framebuffer, bool)

And a struct called VulkanRenderDevice (this is "vkDev" in the book) with these fields:
	device, physical_device, graphics_queue, command_pool, command_buffers: []vk.CommandBuffer,
	swapchain, swapchain_images: []vk.Image, semaphore, render_semaphore
*/

// PART 1 - USING MESH FEOMETRY DATA UN VULKAN (FROM 011) -you can just copy paste the 011 part here 


/* Same programmable vertex pulling (PVP) idea as our OpenGL 008 file, no vertex attributes. The shader gets the raw
vertices AND the raw indices as storage buffers (SSBOs) and looks things up itself, we use cgltf, exactly as in 008. */

VertexData :: struct {
pos: [3]f32,
tc:  [2]f32,
}

/*BUG FIX vs 011: the old struct had a field called `vertex_offset` but the code below writes `mesh.index_size`,
so it would not compile. The correct fields are vertex_size, index_offset and index_size. */
MeshBuffer :: struct {
buffer: vk.Buffer, // one buffer holding vertices first and then indices
memory: vk.DeviceMemory,
vertex_size:  vk.DeviceSize, 
index_offset: vk.DeviceSize, 
index_size:   vk.DeviceSize, 
}

STORAGE_OFFSET_ALIGNMENT :: 256

create_textured_vertex_buffer :: proc(
device: vk.Device,
physical_device: vk.PhysicalDevice,
command_pool: vk.CommandPool,
graphics_queue: vk.Queue,
filename: cstring, // "data/rubber_duck/scene.gltf" ) -> (mesh: MeshBuffer, ok: bool) {
options: cgltf.options
data, parse_result := cgltf.parse_file(options, filename)
if parse_result != .success {
fmt.println("Unable to load", filename)
return {}, false
}
defer cgltf.free(data)
if cgltf.load_buffers(options, data, filename) != .success { return {}, false }

// use only the first primitive of the first mesh
prim := data.meshes[0].primitives[0]
pos_acc, tc_acc: ^cgltf.accessor
for attr in prim.attributes {
#partial switch attr.type {
case .position: pos_acc = attr.data
case .texcoord: tc_acc = attr.data
}
}
count := int(pos_acc.count)
positions := make([]f32, count * 3)
texcoords := make([]f32, count * 2) // stays zeros if the model has no UVs
defer delete(positions)
defer delete(texcoords)
_ = cgltf.accessor_unpack_floats(pos_acc, raw_data(positions), uint(count * 3))
if tc_acc != nil { _ = cgltf.accessor_unpack_floats(tc_acc, raw_data(texcoords), uint(count * 2)) }

// build the vertex list. y and z are swapped as always (the C++ does vec3(v.x, v.z, v.y))
vertices := make([]VertexData, count)
defer delete(vertices)
for i in 0 ..< count {
vertices[i] = VertexData{
pos = {positions[i * 3], positions[i * 3 + 2], positions[i * 3 + 1]},
tc  = {texcoords[i * 2], texcoords[i * 2 + 1]},
		}
	}

// the index list, converted to u32 whatever size the file stored
index_count := int(prim.indices.count)
indices := make([]u32, index_count)
defer delete(indices)
_ = cgltf.accessor_unpack_indices(prim.indices, raw_data(indices), size_of(u32), uint(index_count))

// step 2 - pack vertices + indices into one staging buffer.
// A staging buffer is plain CPU-visible memory we can write to directly.
// The fast GPU-only buffer can't be written by the CPU, so we copy through it.
vertex_bytes := vk.DeviceSize(size_of(VertexData) * count)
index_bytes  := vk.DeviceSize(size_of(u32) * index_count)
index_offset := (vertex_bytes + STORAGE_OFFSET_ALIGNMENT - 1) &~ vk.DeviceSize(STORAGE_OFFSET_ALIGNMENT - 1)
buffer_size  := index_offset + index_bytes
staging_buffer, staging_memory, staging_ok := create_buffer(
device, physical_device, buffer_size,
{.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT},
)
if !staging_ok { return {}, false }
defer destroy_buffer(device, staging_buffer, staging_memory) // freed when we return

// map the memory, copy vertices at the start and indices at index_offset
mapped: rawptr
vk.MapMemory(device, staging_memory, 0, buffer_size, {}, &mapped)
mem.zero(mapped, int(buffer_size)) // clears the padding gap between the two sections
mem.copy(mapped, raw_data(vertices), int(vertex_bytes))
mem.copy(rawptr(uintptr(mapped) + uintptr(index_offset)), raw_data(indices), int(index_bytes))
vk.UnmapMemory(device, staging_memory)
mesh.buffer, mesh.memory, ok = create_buffer(
device, physical_device, buffer_size,
{.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL},
)
if !ok { return {}, false }

// step 3: copy staging -> GPU buffer
copy_buffer(device, command_pool, graphics_queue, staging_buffer, mesh.buffer, buffer_size)
mesh.vertex_size  = vertex_bytes
mesh.index_offset = index_offset
mesh.index_size   = index_bytes
return mesh, true
}

// PART 2 - DESCRIPTOR SETS (FROM 011) - you can copy it from the 011 file 
create_descriptor_pool :: proc(
	device: vk.Device,
	image_count: u32,
	uniform_buffer_count, storage_buffer_count, sampler_count: u32,
) -> (pool: vk.DescriptorPool, ok: bool) {
	pool_sizes := make([dynamic]vk.DescriptorPoolSize)
	defer delete(pool_sizes)

	if uniform_buffer_count > 0 {
		append(&pool_sizes, vk.DescriptorPoolSize{type = .UNIFORM_BUFFER, descriptorCount = image_count * uniform_buffer_count})
	}
	if storage_buffer_count > 0 {
		append(&pool_sizes, vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = image_count * storage_buffer_count})
	}
	if sampler_count > 0 {
		append(&pool_sizes, vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = image_count * sampler_count})
	}

	pool_info := vk.DescriptorPoolCreateInfo{
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = image_count, // one set per swapchain image
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
	}
	result := vk.CreateDescriptorPool(device, &pool_info, nil, &pool)
	return pool, result == .SUCCESS
}

descriptor_set_layout_binding :: proc(binding: u32, kind: vk.DescriptorType, stages: vk.ShaderStageFlags) -> vk.DescriptorSetLayoutBinding {
	return {binding = binding, descriptorType = kind, descriptorCount = 1, stageFlags = stages}
}

create_descriptor_set :: proc(
	device: vk.Device,
	descriptor_pool: vk.DescriptorPool,
	uniform_buffers: []vk.Buffer,
	ubo_size: vk.DeviceSize, // pass size_of(UniformBuffer)
	mesh: MeshBuffer,
	texture_sampler: vk.Sampler,
	texture_view: vk.ImageView,) -> (layout: vk.DescriptorSetLayout, sets: []vk.DescriptorSet, ok: bool) {
	image_count := len(uniform_buffers)

	bindings := [4]vk.DescriptorSetLayoutBinding{
		descriptor_set_layout_binding(0, .UNIFORM_BUFFER, {.VERTEX}),           // mvp matrix
		descriptor_set_layout_binding(1, .STORAGE_BUFFER, {.VERTEX}),           // vertices
		descriptor_set_layout_binding(2, .STORAGE_BUFFER, {.VERTEX}),           // indices
		descriptor_set_layout_binding(3, .COMBINED_IMAGE_SAMPLER, {.FRAGMENT}), // texture
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo{
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = &bindings[0],
	}
	if vk.CreateDescriptorSetLayout(device, &layout_info, nil, &layout) != .SUCCESS {
		return {}, nil, false
	}


layouts := make([]vk.DescriptorSetLayout, image_count)
defer delete(layouts)
for i in 0 ..< image_count { layouts[i] = layout }

alloc_info := vk.DescriptorSetAllocateInfo{
		sType    = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool = descriptor_pool,
		descriptorSetCount = u32(image_count),
		pSetLayouts = raw_data(layouts),
	}
sets = make([]vk.DescriptorSet, image_count)
if vk.AllocateDescriptorSets(device, &alloc_info, raw_data(sets)) != .SUCCESS {
		return layout, sets, false
	}
	for i in 0 ..< image_count {
	ubo_info      := vk.DescriptorBufferInfo{buffer = uniform_buffers[i], offset = 0, range = ubo_size}
	vertices_info := vk.DescriptorBufferInfo{buffer = mesh.buffer, offset = 0, range = mesh.vertex_size}
	indices_info  := vk.DescriptorBufferInfo{buffer = mesh.buffer, offset = mesh.index_offset, range = mesh.index_size}
	image_info    := vk.DescriptorImageInfo{sampler = texture_sampler, imageView = texture_view, imageLayout = .SHADER_READ_ONLY_OPTIMAL}

// one write per binding
writes := [4]vk.WriteDescriptorSet{
{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER, pBufferInfo = &ubo_info},
{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 1, descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &vertices_info},
{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 2, descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &indices_info},
{sType = .WRITE_DESCRIPTOR_SET, dstSet = sets[i], dstBinding = 3, descriptorCount = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, pImageInfo = &image_info},
}
vk.UpdateDescriptorSets(device, u32(len(writes)), &writes[0], 0, nil)
}
return layout, sets, true
}


// PART 3 - THE VK02 DEMO APP - RENDERING THE RUBBER DUCK (NEWER PART HEHE) - ALSO CHAPTER 2 LAST PART 
/* The earlier recipes set up Vulkan without drawing anything. Now we put it all together:
main() -> init GLFW, create the window, run init_vulkan(), loop calling draw_overlay(), then clean up
init_vulkan() -> instance, debug, surface, device, shaders, duck mesh, texture, depth buffer, descriptors, pipeline
draw_overlay() -> every frame: acquire a swapchain image, update the mvp matrix, record + submit commands, present
The "overlay" in the name is because the geometry shader draws a wireframe on top of the textured duck. */

// window size and these are untyped constants so they work as u32, i32 or f32 wherever we use them
SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

VulkanState :: struct {
instance: vk.Instance,
messenger: vk.DebugUtilsMessengerEXT, // validation layer messages get printed through this
surface: vk.SurfaceKHR, // the link between vulkan and the glfw window

// shader modules: vertex pulls the mesh, geometry makes the wireframe, fragment applies the texture
vert_shader: vk.ShaderModule,
frag_shader: vk.ShaderModule,
geom_shader: vk.ShaderModule,
mesh: MeshBuffer, // duck vertices + indices in one storage buffer
// one uniform buffer (holding the mvp matrix) perr swapchain image, so we never overwrite one the gpu is still reading
uniform_buffers: []vk.Buffer,
uniform_buffers_memory: []vk.DeviceMemory,

// the duck texture
texture_image: vk.Image,
texture_memory: vk.DeviceMemory,
texture_view: vk.ImageView,
texture_sampler: vk.Sampler,

// depth buffer, so near parts of the duck hide far parts
depth_image: vk.Image,
depth_memory: vk.DeviceMemory,
depth_view: vk.ImageView,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,
descriptor_sets:  []vk.DescriptorSet, // one per swapchain image
render_pass: vk.RenderPass,
pipeline_layout: vk.PipelineLayout,
graphics_pipeline: vk.Pipeline,
framebuffers: []vk.Framebuffer, // one per swapchain image
}

window : glfw.WindowHandle 
vk_state : VulkanState
vk_dev : VulkanRenderDevice 

vk_check :: proc(result: vk.Result , loc := #caller_location) {
if result != .SUCCESS { 
fmt.eprintln("VULKAN ERROR:" , result , "at" , loc) 
os.exit(1) 
} }

//builds one entry of the pipeline shader list 
shader_stage_info :: proc(stage :vk.ShaderStageFlags , module : vk.ShaderModule , entry : cstring) -> vk.PipelineShaderCreateInfo {
return { 
sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
stage  = stage,
module = module,
pName  = entry, // the function name inside the shader, always "main" for GLSL  (opengl shader language can be used for vulkan) 
} }

//GLFW keyboard callback , we only did esc to close the window
// It has to be `proc "c"` because GLFW is a C library calling back into us.  (VERY IMPORTANT) 
key_callback :: proc "c" (w: glfw.WindowHandle, key, scancode, action, mods: i32) {
if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
glfw.SetWindowShouldClose(w, true)
}
}

// UNIFORM BUFFERS - CREATE ONE PER SWAPCHAIN IMAGE , AND A PROC TO WRITE THE MVP MATRIX INTO ONE OF THEM 
create_frame_uniform_buffers :: proc() -> bool {
image_count := len(vk_dev.swapchain_images)
vk_state.uniform_buffers = make([]vk.Buffer, image_count)
vk_state.uniform_buffers_memory = make([]vk.DeviceMemory, image_count)

for i in 0 ..< image_count {
ok: bool

// HOST_VISIBLE + HOST_COHERENT = the CPU can write to it directly every frame with no extra flushing
vk_state.uniform_buffers[i], vk_state.uniform_buffers_memory[i], ok = create_buffer(
vk_dev.device, vk_dev.physical_device, size_of(UniformBuffer),
{.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, 
)
if !ok { return false }
}
return true
}
// copy a UniformBuffer struct into the uniform buffer that belongs to this swapchain image
update_frame_uniform_buffer :: proc(image_index: u32, ubo: UniformBuffer) {
	local := ubo // proc parameters can't have their address taken in Odin, so copy to a local first
	data: rawptr
	vk_check(vk.MapMemory(vk_dev.device, vk_state.uniform_buffers_memory[image_index], 0, size_of(UniformBuffer), {}, &data))
	mem.copy(data, &local, size_of(UniformBuffer))
	vk.UnmapMemory(vk_dev.device, vk_state.uniform_buffers_memory[image_index])
}


// init_vulkan: all the long setup code from the previous recipes, in order


init_vulkan :: proc() -> bool {
ok: bool

// 1. Create the Vulkan instance, then load the instance level function pointers (this replaces what Volk does in C++),then set up the debug callbacks (validation layer messages).
vk_state.instance, ok = create_instance()
if !ok { return false }
vk.load_proc_addresses_instance(vk_state.instance)
vk_state.messenger, ok = setup_debug_callbacks(vk_state.instance)
if !ok { return false }

// Create a window surface attached to the GLFW window and our Vulkan instance
if glfw.CreateWindowSurface(vk_state.instance, window, nil, &vk_state.surface) != .SUCCESS { return false }

// Initialise the render device (physical + logical device, queues, swapchain, command pool, semaphores).We turn on geometryShader because the wireframe overlay is made by a geometry shader.
features := vk.PhysicalDeviceFeatures{geometryShader = true}
if !init_vulkan_render_device(&vk_dev, vk_state.instance, vk_state.surface, SCREEN_WIDTH, SCREEN_HEIGHT, features) { return false }
vk.load_proc_addresses_device(vk_dev.device) // device-level function pointers (skip if your init already does this)

// Create shader modules for the vertex, fragment and geometry shaders. Odin has no built-in glslang, so these are PRE-COMPILED SPIR-V files. Compile them once with glslangValidator -V VK02.vert -o VK02.vert.spv   (same for .frag and .geom)
vk_state.vert_shader, ok = create_shader_module(vk_dev.device, "data/shaders/chapter03/VK02.vert.spv")
if !ok { return false }
vk_state.frag_shader, ok = create_shader_module(vk_dev.device, "data/shaders/chapter03/VK02.frag.spv")
if !ok { return false }
vk_state.geom_shader, ok = create_shader_module(vk_dev.device, "data/shaders/chapter03/VK02.geom.spv")
if !ok { return false }

//Load the rubber duck into one storage buffer (PART 1 above), then make the uniform buffers
vk_state.mesh, ok = create_textured_vertex_buffer(
vk_dev.device, vk_dev.physical_device, vk_dev.command_pool, vk_dev.graphics_queue,
"data/rubber_duck/scene.gltf",
)
if !ok || !create_frame_uniform_buffers() {
fmt.println("Cannot create data buffers")
return false
}
// The pipeline shader stages, built from the modules we just created
shader_stages := [3]vk.PipelineShaderStageCreateInfo{
shader_stage_info({.VERTEX},   vk_state.vert_shader, "main"),
shader_stage_info({.FRAGMENT}, vk_state.frag_shader, "main"),
shader_stage_info({.GEOMETRY}, vk_state.geom_shader, "main"),
}

// Load the texture from file, make an image view for it and a sampler (how the GPU filters/wraps the texture)
if !create_texture_image(
vk_dev.device, vk_dev.physical_device, vk_dev.command_pool, vk_dev.graphics_queue,
"data/rubber_duck/DuckCM.png", &vk_state.texture_image, &vk_state.texture_memory,
) { return false }
vk_state.texture_view, ok = create_image_view(vk_dev.device, vk_state.texture_image, .R8G8B8A8_UNORM, {.COLOR})
if !ok { return false }
vk_state.texture_sampler, ok = create_texture_sampler(vk_dev.device)
if !ok { return false }

// Create the depth buffer
vk_state.depth_image, vk_state.depth_memory, vk_state.depth_view, ok = create_depth_resources(&vk_dev, SCREEN_WIDTH, SCREEN_HEIGHT)
if !ok { return false } 


/* 9. descriptor pool + sets (PART 2 above), render pass, pipeline layout and the graphics pipeline.
 pool counts are PER swapchain image: 1 uniform buffer, 2 storage buffers (vertices + indices), 1 texture sampler. */
vk_state.descriptor_pool, ok = create_descriptor_pool(vk_dev.device, u32(len(vk_dev.swapchain_images)), 1, 2, 1)
if !ok { return false }

vk_state.descriptor_set_layout, vk_state.descriptor_sets, ok = create_descriptor_set(
vk_dev.device, vk_state.descriptor_pool, vk_state.uniform_buffers, size_of(UniformBuffer),
vk_state.mesh, vk_state.texture_sampler, vk_state.texture_view,
)
if !ok { return false }

// this is the only render pass in the app, so it is both the "first" and the "last" one andd it clears color + depth
// at the start and leaves the image ready for presenting at the end
vk_state.render_pass, ok = create_color_and_depth_render_pass(
vk_dev.device, true,
RenderPassCreateInfo{clear_color = true, clear_depth = true, flags = {.First, .Last}},
)
if !ok { return false }

vk_state.pipeline_layout, ok = create_pipeline_layout(vk_dev.device, vk_state.descriptor_set_layout)
if !ok { return false }
vk_state.graphics_pipeline, ok = create_graphics_pipeline(
vk_dev.device, SCREEN_WIDTH, SCREEN_HEIGHT,
vk_state.render_pass, vk_state.pipeline_layout, shader_stages[:],
)
if !ok {
fmt.println("Failed to create pipeline HOHO")
return false
}
// one framebuffer per swapchain image: it joins that image (color) with the shared depth buffer
vk_state.framebuffers, ok = create_color_and_depth_framebuffers(
&vk_dev, vk_state.render_pass, vk_state.depth_view, SCREEN_WIDTH, SCREEN_HEIGHT,
)
return ok
}

// fill_command_buffer: record the drawing commands for ONE swapchain image

/* we record only the buffer we are about to submit (image_index) instead of all of them, because that's the only one we use this frame. */
fill_command_buffer :: proc(image_index: u32) -> bool {
cmd := vk_dev.command_buffers[image_index]

// SIMULTANEOUS_USE - the buffer may be resubmitted while a previous submit of it is still pending
begin_info := vk.CommandBufferBeginInfo{
sType = .COMMAND_BUFFER_BEGIN_INFO,
flags = {.SIMULTANEOUS_USE},
}
if vk.BeginCommandBuffer(cmd, &begin_info) != .SUCCESS { return false }
// what to clear the attachments to: white background, and depth = 1.0 (the farthest possible value)
clear_values := [2]vk.ClearValue{
{color = {float32 = {1.0, 1.0, 1.0, 1.0}}},
{depthStencil = {depth = 1.0, stencil = 0}},
}
render_pass_info := vk.RenderPassBeginInfo{
sType = .RENDER_PASS_BEGIN_INFO,
renderPass = vk_state.render_pass,
framebuffer = vk_state.framebuffers[image_index],
renderArea  = {offset = {0, 0}, extent = {SCREEN_WIDTH, SCREEN_HEIGHT}},
clearValueCount = u32(len(clear_values)),
pClearValues  = &clear_values[0],
}
vk.CmdBeginRenderPass(cmd, &render_pass_info, .INLINE)

vk.CmdBindPipeline(cmd, .GRAPHICS, vk_state.graphics_pipeline)
// bind the descriptor set for this image: mvp + vertices + indices + texture
vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vk_state.pipeline_layout, 0, 1, &vk_state.descriptor_sets[image_index], 0, nil)

/* programmable vertex pulling - there is no vertex buffer bound so we just say "draw N vertices" where N is the index
 count, and the vertex shader uses gl_VertexIndex to look up the index and then the vertex in the storage buffers. */
index_count := u32(vk_state.mesh.index_size / size_of(u32))
vk.CmdDraw(cmd, index_count, 1, 0, 0)
vk.CmdEndRenderPass(cmd)
return vk.EndCommandBuffer(cmd) == .SUCCESS
}


// draw_overlay: does the bulk of the rendering job, called once per frame

draw_overlay :: proc() -> bool {
// Acquire the next available image from the swapchain. `vk_dev.semaphore` gets signalled when the image is ready.
image_index: u32
vk_check(vk.AcquireNextImageKHR(vk_dev.device, vk_dev.swapchain, max(u64), vk_dev.semaphore, vk.Fence(0), &image_index))
// reset the command pool: this throws away all old recorded commands so we can record fresh ones
vk_check(vk.ResetCommandPool(vk_dev.device, vk_dev.command_pool, {}))

// fill in the uniform buffer. Rotate the model around the vertical axis, like the OpenGL examples in the previous chapter.
width, height := glfw.GetFramebufferSize(window)
ratio := f32(width) / f32(height)

/*the C++ builds this as: m1 = rotate( translate(I, (0, 0.5, -1.5)) * rotate(I, pi, (1,0,0)), time, (0,1,0) )
glm::rotate(m, a, axis) means m * R(a, axis), so in matrix form that is: Translate * RotateX(pi) * RotateY(time)
- RotateX(pi) flips the duck upside down, which cancels out Vulkan's upside-down Y axis
-Translate moves it a bit up and away from the camera
-RotateY(time) is the spinning */
translate := linalg.matrix4_translate_f32({0.0, 0.5, -1.5})
flip_y := linalg.matrix4_rotate_f32(linalg.PI, {1, 0, 0})
spin := linalg.matrix4_rotate_f32(f32(glfw.GetTime()), {0, 1, 0})
m1 := translate * flip_y * spin // in Odin `*` between matrices is real matrix multiplication


// 45 degrees field of view. (The book passes 45.0f straight into glm::perspective, which is why we convert to radians here.)
	// If the duck looks cut off or inside-out, try flip_z_axis = false on the end of this call, it depends on your depth setup.
	p := linalg.matrix4_perspective_f32(linalg.to_radians(f32(45.0)), ratio, 0.1, 1000.0)

	ubo := UniformBuffer{mvp = p * m1}
	update_frame_uniform_buffer(image_index, ubo)

	// 3. Fill in the command buffer (see fill_command_buffer above)
	if !fill_command_buffer(image_index) { return false }

/* 4. Submit the command buffer to the graphics queue like  -wait on `semaphore` (the image is ready) but only at the COLOR_ATTACHMENT_OUTPUT stage, so the GPU can
start vertex work early and only has to wait before it actually writes pixels 
- signal `render_semaphore` when rendering is done */
wait_stages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
submit_info := vk.SubmitInfo{
sType = .SUBMIT_INFO,
waitSemaphoreCount   = 1,
pWaitSemaphores  = &vk_dev.semaphore,
pWaitDstStageMask  = &wait_stages,
commandBufferCount   = 1,
pCommandBuffers  = &vk_dev.command_buffers[image_index],
signalSemaphoreCount = 1,
pSignalSemaphores = &vk_dev.render_semaphore,
}
vk_check(vk.QueueSubmit(vk_dev.graphics_queue, 1, &submit_info, vk.Fence(0)))

// Present the rendered image on screen, but only after render_semaphore says rendering has finished
present_info := vk.PresentInfoKHR{
sType   = .PRESENT_INFO_KHR,
waitSemaphoreCount = 1,
pWaitSemaphores  = &vk_dev.render_semaphore,
swapchainCount = 1,
pSwapchains = &vk_dev.swapchain,
pImageIndices = &image_index,
}
vk_check(vk.QueuePresentKHR(vk_dev.graphics_queue, &present_info))

// wait until the GPU is completely done. Very simple and slow, but it means we never touch something the GPU still uses.
vk_check(vk.DeviceWaitIdle(vk_dev.device))
return true
}

// terminate_vulkan - destroy everything in the REVERSE order we created it (the book does this in the termination stage)
