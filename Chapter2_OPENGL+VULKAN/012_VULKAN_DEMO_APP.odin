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
