// will be using the rubber_duck asset here 
// BEEN USING LAZYVIM for this and it's awesome but sometimes a hassel to use 

// the normal imports above every file 
package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"
import stbi "vendor:stb/image"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}

// PART 1 - LOADING MESH GEOMETRY  
/* As we should be using Assimp here for C++ , as odin vendor does not have Assimp , we would be using something else - 
 * SO instead of using Assimp , we parse a plain wavefront .obj file ourselves , it's a simple text format and this keeps the project free of any extra C library 
 * We will export our duck model as .obj (BLENDER - FILE -> EXPORT -> Wavefront) and point main() at it 
 * Output has the exact same shape the book produces, a list of vertices (position + texture coordinate) and a list of u32 indices  */ 

VertexData :: struct { 
 pos : [3]f32 , 
 tc: [2]f32 ,
}

/*size_of(VertexData) == 20 bytes, tightly packed. That matches the `struct VertexData { float x, y, z; float u, v; }` in the vertex shader, because SSBOs use std430 layout, which doesn't pad this struct.
 Like the book, we only take the first primitive of the first mesh (mesh->mMeshes[0]). glTF stores each attribute (position, texcoord, ...) in an "accessor"; cgltf can unpack any accessor into a plain float array.*/ 

load_gltf :: proc(filename: cstring) -> (vertices: [dynamic]VertexData, indices: [dynamic]u32, ok: bool) {
	options: cgltf.options
	data, result := cgltf.parse_file(options, filename)
	if result != .success { return {}, {}, false }
	defer cgltf.free(data)

// parse_file only reads the .gltf json, this also loads Duck0.bin (the raw vertex data it points to, looked up next to the .gltf file)
if cgltf.load_buffers(options, data, filename) != .success { return {}, {}, false }

if len(data.meshes) == 0 || len(data.meshes[0].primitives) == 0 { return {}, {}, false }
prim := data.meshes[0].primitives[0]
if prim.type != .triangles { return {}, {}, false }

pos_acc, tc_acc: ^cgltf.accessor
for attr in prim.attributes {
if attr.type == .position && attr.index == 0 { pos_acc = attr.data }
if attr.type == .texcoord && attr.index == 0 { tc_acc = attr.data }
}
if pos_acc == nil { return {}, {}, false }

count := int(pos_acc.count)
positions := make([]f32, count * 3)
defer delete(positions)
_ = cgltf.accessor_unpack_floats(pos_acc, raw_data(positions), uint(count * 3))

texcoords: []f32
defer delete(texcoords)
if tc_acc != nil && int(tc_acc.count) == count {
	texcoords = make([]f32, count * 2)
	_ = cgltf.accessor_unpack_floats(tc_acc, raw_data(texcoords), uint(count * 2))
}

for i in 0 ..< count {
tc: [2]f32
if texcoords != nil { tc = {texcoords[i * 2], texcoords[i * 2 + 1]} }
// same y/z swap as required: vec3(v.x, v.z, v.y)
	append(&vertices, VertexData{pos = {positions[i * 3], positions[i * 3 + 2], positions[i * 3 + 1]}, tc = tc})
}

if prim.indices != nil {
n := int(prim.indices.count)
resize(&indices, n)
// the file may store indices as u8/u16/u32, this converts to u32
_ = cgltf.accessor_unpack_indices(prim.indices, raw_data(indices), size_of(u32), uint(n))
} else {
for i in 0 ..< count { append(&indices, u32(i)) }
}
return vertices, indices, len(vertices) > 0 && len(indices) > 0
}

// PART 2 - UPLOADING THE MESH INTO ONE SHADER STORAGE BUFFER (SSBO)
/* programmable vertex pulling (PVP) - vertices and indices live together in a single GPU buffer , the vertex shader reads them itself 
 * from two storage buffer bindings (bindings 1 and 2) , each pinpointing at a different slice of this one buffer */ 
MeshBuffer :: struct {
	buffer:       vk.Buffer,
	memory:       vk.DeviceMemory,
	vertex_size:  vk.DeviceSize, // bytes of vertex data, starts at offset 0
	index_offset: vk.DeviceSize, // where the index data starts
	index_size:   vk.DeviceSize, // bytes of index data
}
align_up :: proc(value, alignment: vk.DeviceSize) -> vk.DeviceSize {
	return (value + alignment - 1) / alignment * alignment
}

create_textured_vertex_buffer :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, command_pool: vk.CommandPool, graphics_queue: vk.Queue, filename: cstring) -> (mesh: MeshBuffer, ok: bool) {
vertices, indices, loaded := load_gltf(filename)
if !loaded {
	fmt.println("Unable to load", filename)
	return {}, false
}
defer delete(vertices)
defer delete(indices)

mesh.vertex_size = vk.DeviceSize(size_of(VertexData) * len(vertices))
mesh.index_size = vk.DeviceSize(size_of(u32) * len(indices))

// IMPORTANT FIX - later we bind the index half of this buffer
// as its own descriptor with `offset = vertex_size`. Vulkan requires that offset to be a multiple of minStorageBufferOffsetAlignment (often 16, up to 256 on some GPUs). Our vertices are 20 bytes each, so
// vertex_size is NOT automatically aligned, the book's code would trigger a validation error on many meshes. We just pad up to alignment.

props: vk.PhysicalDeviceProperties
vk.GetPhysicalDeviceProperties(physical_device, &props)
mesh.index_offset = align_up(mesh.vertex_size, props.limits.minStorageBufferOffsetAlignment)

buffer_size := mesh.index_offset + mesh.index_size

// staging buffer: cpu-visible scratch memory we write into first
staging_buffer, staging_memory, staging_ok := create_buffer(device, physical_device, buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
if !staging_ok { return {}, false }
defer destroy_buffer(device, staging_buffer, staging_memory)

data: rawptr
vk_check(vk.MapMemory(device, staging_memory, 0, buffer_size, {}, &data), "mapping staging memory")
mem.zero(data, int(buffer_size)) // clears the alignment padding
mem.copy(data, raw_data(vertices), int(mesh.vertex_size))
mem.copy(rawptr(uintptr(data) + uintptr(mesh.index_offset)), raw_data(indices), int(mesh.index_size))
vk.UnmapMemory(device, staging_memory)

// the real buffer foor gpu-only memory, usable as a copy target AND as an SSBO
created: bool
mesh.buffer, mesh.memory, created = create_buffer(device, physical_device, buffer_size, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
if !created { return {}, false }

copy_buffer(device, command_pool, graphics_queue, staging_buffer, mesh.buffer, buffer_size)
return mesh, true
}

copy_buffer :: proc(device: vk.Device, command_pool: vk.CommandPool, graphics_queue: vk.Queue, src, dst: vk.Buffer, size: vk.DeviceSize) {
cb := begin_single_time_commands(device, command_pool)
region := vk.BufferCopy{srcOffset = 0, dstOffset = 0, size = size}
vk.CmdCopyBuffer(cb, src, dst, 1, &region)
end_single_time_commands(device, command_pool, graphics_queue, cb)
}


// PART 3 - VULKAN DESCRIPTOR SETS 
/* a discriptor is a handle/pointer to one resource ( a buffer or a texture) , a discriptor set is a bundle of them , and it's the only way 
shaders can get a buffers and textures in vulkan, it has 4 steps - 
step 1 - create a pool - where descriptor sets gets allocated from 
step 2 - create a layout - describe what's in the set , which binding is what type , visible to which shader stage 
step 3 - allocate sets - one per swapchain image , all using that layout 
step 4 - update the sets - actually point each binding at a real buffer/texture */ 

IMAGE_COUNT :: 3 // pretend swapchain image count ( no real swapchain in this file yet)

UniformBuffer :: struct { 
mvp : matrix[4,4]f32 ,
}

VulkanState :: struct { 
uniform_buffers : [dynamic]vk.Buffer ,
uniform_buffers_memory: [dynamic]vk.DeviceMemory , 
mesh: MeshBuffer , 
texture_view : vk.ImageView ,
texture_sampler : vk.Sampler , 
descriptor_pool : vk.DescriptorPool , 
descriptor_set_layout : vk.DescriptorSetLayout , 
descriptor_sets ; [dynamic]vk.DescriptorSet , 
} 

// step 1 - the pool must hold enough of each descriptor type for every set we will allocate , we make one set per swapchain image , so every count is multiplied by image_count 

create_descriptor_pool :: proc( device : vk.Device , image_count , uniform_buffer_count , storage_buffer_count , sampler_count: u32 ) -> (pool: vk.DescriptorPool , ok: bool) {
pool_sizes : [dynamic]vk,DescriptorPoolSize 
defer delete(pool_sizes) 

if uniform_buffer_count > 0 {
 append(&pool_sizes , vk.DescriptorPoolSize{type = .UNIFORM_BUFFER , descriptorCount = image_count * uniform_buffer_count} ) 
} 
if storage_buffer_count > 0 {
append(&pool_sizes , vk.DescriptorPoolSize{type = .STORAGE_BUFFER , descriptorCount = image_count * storage_buffer_count } ) 
} 
if sampler_count > 0 { 
append(&pool_sizes , vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER , descriptorCount = image_count * sampler_count } ) 
}
pool_info := vk.DescriptorPoolCreateInfo{
sType    = .DESCRIPTOR_POOL_CREATE_INFO,
maxSets   = image_count,
poolSizeCount = u32(len(pool_sizes)),
pPoolSizes    = raw_data(pool_sizes) if len(pool_sizes) > 0 else nil,
}
result := vk.CreateDescriptorPool(device, &pool_info, nil, &pool)
return pool, result == .SUCCESS
}
// helper - one entry of the layout - binding N in this kind of resource and these shaders may touch 
descriptor_set_layout_binding :: proc(binding : u32 , kind : vk.DescriptorType , stages : vk.ShaderStageFlags) -> vk.DescriptorSetLayoutBinding { 
return {binding = binding, descriptorType = kind, descriptorCount = 1, stageFlags = stages}
}

//STEP -2 - the layout , these are 4 bindings must match the "layout(binding = N)" declarations in the shaders 
/* 0 = uniform buffer (mvp matrix) - vertex shader 
   1 = storage buffer (vertices) - vertex shader 
   2 = storage buffer (indices) - vertex shader 
   3 = texture + sampler - fragment shader */ 

create_descriptor_set_layout :: proc(device : vk.Device) -> (layout : vk.DescriptorSetLayout , ok : bool ) { 
bindings := [4]vk.DescriptorSetLayoutBinding( 
descriptor_set_layout_binding(0 , .UNIFORM_BUFFER , {.VERTEX}) , 
descriptor_set_layout_binding(1, .STORAGE_BUFFER, {.VERTEX}),
descriptor_set_layout_binding(2, .STORAGE_BUFFER, {.VERTEX}),
descriptor_set_layout_binding(3, .COMBINED_IMAGE_SAMPLER, {.FRAGMENT}),
}

layout _info := vk.DescriptorSetLayoutCreateInfo {
sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO , 
bindingCount = u32(len(bindings)) , 
pBindings = &bindings[0] , } 
result := vk.CreateDescriptorSetLayout(device, &layout_info, nil, &layout)
return layout, result == .SUCCESS
}

// STEP 3 - allocate one set per swapchain image , all sharing the layout 
allocate_descriptor_sets :: proc(device : vk.Device , state : ^VulkanStae , image_count : u32 ) -> bool { 
layouts := make([]vk.DescriptorSetLayout , image_count) 
defer delete(layouts) 
for &1 in layouts { 1 = state.descriptor_set_layout) 
lloc_info := vk.DescriptorSetAllocateInfo{
sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
descriptorPool     = state.descriptor_pool,
descriptorSetCount = image_count,
pSetLayouts        = raw_data(layouts),
}
resize(&state.descriptor_sets, int(image_count))
return vk.AllocateDescriptorSets(device, &alloc_info, raw_data(state.descriptor_sets)) == .SUCCESS
}

/* STEP 4 - point every binding of every set at a real resource , this is the vulkan analougue of glBindBufferBase/glBindTexture , with key difference that is it's done once up front 
and not for every frame (this is the reason we can't swap textures from frame to frame) */ 

update_descriptor_sets :: proc(device : vk.Device , state: ^VulkanState , image_count:u32) { 
for i in 0 ..< int(image_count) { 
//binding 0 - this is frame uniform buffer 
ubo_info := vk.DescriptorBufferInfo{buffer = state.uniform_buffers[i] , offset = 0 , range - vk.DeviceSize(size_of(UniformBuffer))} 
//binding 2 - the first slice of the mesh buffer - vertices 
vertices_info := vk.DescriptorBufferInfo{ buffer = state.mesh.buffer , offset = 0 , range = state.mesh.vertex_size} 
// binding 2: the SECOND slice of the SAME buffer indices
indices_info := vk.DescriptorBufferInfo{buffer = state.mesh.buffer, offset = state.mesh.index_offset, range = state.mesh.index_size}
// binding 3: texture + sampler
image_info := vk.DescriptorImageInfo{sampler = state.texture_sampler, imageView = state.texture_view, imageLayout = .SHADER_READ_ONLY_OPTIMAL}
writes := [4]vk.WriteDescriptorSet{
	{sType = .WRITE_DESCRIPTOR_SET, dstSet = state.descriptor_sets[i], dstBinding = 0, dstArrayElement = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER, pBufferInfo = &ubo_info},
	{sType = .WRITE_DESCRIPTOR_SET, dstSet = state.descriptor_sets[i], dstBinding = 1, dstArrayElement = 0, descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &vertices_info},
	{sType = .WRITE_DESCRIPTOR_SET, dstSet = state.descriptor_sets[i], dstBinding = 2, dstArrayElement = 0, descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &indices_info},
	{sType = .WRITE_DESCRIPTOR_SET, dstSet = state.descriptor_sets[i], dstBinding = 3, dstArrayElement = 0, descriptorCount = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, pImageInfo = &image_info},
}
vk.UpdateDescriptorSets(device, u32(len(writes)), &writes[0], 0, nil)
}
}


// TEXTURE SUPPORT - FROM OLD FILES 

create_image :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, width, height: u32, format: vk.Format, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags) -> (image: vk.Image, image_memory: vk.DeviceMemory, ok: bool) {
image_info := vk.ImageCreateInfo{
sType = .IMAGE_CREATE_INFO, imageType = .D2, format = format, extent = {width, height, 1},
mipLevels = 1, arrayLayers = 1, samples = {._1}, tiling = tiling, usage = usage,
sharingMode = .EXCLUSIVE, initialLayout = .UNDEFINED,
}
if vk.CreateImage(device, &image_info, nil, &image) != .SUCCESS { return {}, {}, false }

mem_requirements: vk.MemoryRequirements
vk.GetImageMemoryRequirements(device, image, &mem_requirements)
alloc_info := vk.MemoryAllocateInfo{
sType = .MEMORY_ALLOCATE_INFO, allocationSize = mem_requirements.size,
	memoryTypeIndex = find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties),
}
if vk.AllocateMemory(device, &alloc_info, nil, &image_memory) != .SUCCESS { return {}, {}, false }
vk.BindImageMemory(device, image, image_memory, 0)
return image, image_memory, true
}

create_texture_sampler :: proc(device: vk.Device) -> (sampler: vk.Sampler, ok: bool) {
	sampler_info := vk.SamplerCreateInfo{
		sType = .SAMPLER_CREATE_INFO, magFilter = .LINEAR, minFilter = .LINEAR, mipmapMode = .LINEAR,
		addressModeU = .REPEAT, addressModeV = .REPEAT, addressModeW = .REPEAT,
		maxAnisotropy = 1, borderColor = .INT_OPAQUE_BLACK, compareOp = .ALWAYS,
	}
	result := vk.CreateSampler(device, &sampler_info, nil, &sampler)
	return sampler, result == .SUCCESS
}

copy_buffer_to_image :: proc(device: vk.Device, command_pool: vk.CommandPool, graphics_queue: vk.Queue, buffer: vk.Buffer, image: vk.Image, width, height: u32) {
	cb := begin_single_time_commands(device, command_pool)
	region := vk.BufferImageCopy{
		bufferOffset = 0, bufferRowLength = 0, bufferImageHeight = 0,
		imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		imageOffset = {0, 0, 0}, imageExtent = {width, height, 1},
	}
	vk.CmdCopyBufferToImage(cb, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)
	end_single_time_commands(device, command_pool, graphics_queue, cb)
}
transition_image_layout :: proc(device: vk.Device, command_pool: vk.CommandPool, graphics_queue: vk.Queue, image: vk.Image, old_layout, new_layout: vk.ImageLayout) {
	cb := begin_single_time_commands(device, command_pool)

	barrier := vk.ImageMemoryBarrier{
		sType = .IMAGE_MEMORY_BARRIER, oldLayout = old_layout, newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED, dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {aspectMask = {.COLOR}, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1},
	}
	source_stage, destination_stage: vk.PipelineStageFlags

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		barrier.dstAccessMask = {.TRANSFER_WRITE}
		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}
		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	}
	vk.CmdPipelineBarrier(cb, source_stage, destination_stage, {}, 0, nil, 0, nil, 1, &barrier)

	end_single_time_commands(device, command_pool, graphics_queue, cb)
}

create_texture_image :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, command_pool: vk.CommandPool, graphics_queue: vk.Queue, filename: cstring) -> (image: vk.Image, image_memory: vk.DeviceMemory, ok: bool) {
	tex_width, tex_height, tex_channels: i32
	pixels := stbi.load(filename, &tex_width, &tex_height, &tex_channels, 4)
	if pixels == nil {
		fmt.println("Failed to load [", filename, "] texture")
		return {}, {}, false
	}
	defer stbi.image_free(pixels)

	image_size := vk.DeviceSize(tex_width * tex_height * 4)

	staging_buffer, staging_memory, staging_ok := create_buffer(device, physical_device, image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	if !staging_ok { return {}, {}, false }
	defer destroy_buffer(device, staging_buffer, staging_memory)

	data: rawptr
	vk.MapMemory(device, staging_memory, 0, image_size, {}, &data)
	mem.copy(data, pixels, int(image_size))
	vk.UnmapMemory(device, staging_memory)

	created: bool
	image, image_memory, created = create_image(device, physical_device, u32(tex_width), u32(tex_height), .R8G8B8A8_UNORM, .OPTIMAL, {.TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL})
	if !created { return {}, {}, false }

	transition_image_layout(device, command_pool, graphics_queue, image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	copy_buffer_to_image(device, command_pool, graphics_queue, staging_buffer, image, u32(tex_width), u32(tex_height))
	transition_image_layout(device, command_pool, graphics_queue, image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)

	return image, image_memory, true
}

// REUSED HELPERS (buffers, command buffers, instance/device setup)
find_memory_type :: proc(physical_device: vk.PhysicalDevice, type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)
	for i in 0 ..< mem_properties.memoryTypeCount {
		bit := u32(1) << i
		if (type_filter & bit) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties == properties) {
			return i
		}
	}
	return 0xFFFFFFFF
}

create_buffer :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) -> (buffer: vk.Buffer, buffer_memory: vk.DeviceMemory, ok: bool) {
	buffer_info := vk.BufferCreateInfo{sType = .BUFFER_CREATE_INFO, size = size, usage = usage, sharingMode = .EXCLUSIVE}
	if vk.CreateBuffer(device, &buffer_info, nil, &buffer) != .SUCCESS { return {}, {}, false }
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &mem_requirements)
	alloc_info := vk.MemoryAllocateInfo{sType = .MEMORY_ALLOCATE_INFO, allocationSize = mem_requirements.size, memoryTypeIndex = find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties)}
	if vk.AllocateMemory(device, &alloc_info, nil, &buffer_memory) != .SUCCESS { return {}, {}, false }
	vk.BindBufferMemory(device, buffer, buffer_memory, 0)
	return buffer, buffer_memory, true
}

destroy_buffer :: proc(device: vk.Device, buffer: vk.Buffer, buffer_memory: vk.DeviceMemory) {
	vk.DestroyBuffer(device, buffer, nil)
	vk.FreeMemory(device, buffer_memory, nil)
}

begin_single_time_commands :: proc(device: vk.Device, command_pool: vk.CommandPool) -> vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo{sType = .COMMAND_BUFFER_ALLOCATE_INFO, commandPool = command_pool, level = .PRIMARY, commandBufferCount = 1}
	command_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(device, &alloc_info, &command_buffer)
	begin_info := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO, flags = {.ONE_TIME_SUBMIT}}
	vk.BeginCommandBuffer(command_buffer, &begin_info)
	return command_buffer
}

end_single_time_commands :: proc(device: vk.Device, command_pool: vk.CommandPool, graphics_queue: vk.Queue, command_buffer: vk.CommandBuffer) {
	cb := command_buffer
	vk.EndCommandBuffer(cb)
	submit_info := vk.SubmitInfo{sType = .SUBMIT_INFO, commandBufferCount = 1, pCommandBuffers = &cb}
	vk.QueueSubmit(graphics_queue, 1, &submit_info, {})
	vk.QueueWaitIdle(graphics_queue)
	vk.FreeCommandBuffers(device, command_pool, 1, &cb)
}

create_image_view :: proc(device: vk.Device, image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags) -> (vk.ImageView, bool) {
	view_info := vk.ImageViewCreateInfo{sType = .IMAGE_VIEW_CREATE_INFO, image = image, viewType = .D2, format = format, subresourceRange = {aspectMask = aspect_flags, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1}}
	view: vk.ImageView
	result := vk.CreateImageView(device, &view_info, nil, &view)
	return view, result == .SUCCESS
}

create_instance :: proc() -> vk.Instance {
	layers := []cstring{"VK_LAYER_KHRONOS_validation"}
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	app_info := vk.ApplicationInfo{sType = .APPLICATION_INFO, pApplicationName = "Vulkan", apiVersion = vk.API_VERSION_1_1}
	create_info := vk.InstanceCreateInfo{sType = .INSTANCE_CREATE_INFO, pApplicationInfo = &app_info, enabledLayerCount = u32(len(layers)), ppEnabledLayerNames = raw_data(layers), enabledExtensionCount = u32(len(glfw_extensions)), ppEnabledExtensionNames = raw_data(glfw_extensions)}
	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "creating instance")
	vk.load_proc_addresses(instance)
	return instance
}

find_suitable_physical_device :: proc(instance: vk.Instance, selector: proc(device: vk.PhysicalDevice) -> bool) -> (vk.PhysicalDevice, bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 { return {}, false }
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	for device in devices { if selector(device) { return device, true } }
	return {}, false
}

find_queue_families :: proc(device: vk.PhysicalDevice, desired_flags: vk.QueueFlags) -> u32 {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))
	for family, i in families { if family.queueCount > 0 && (family.queueFlags & desired_flags == desired_flags) { return u32(i) } }
	return 0
}

create_device :: proc(physical_device: vk.PhysicalDevice, device_features: vk.PhysicalDeviceFeatures, graphics_family: u32) -> (vk.Device, vk.Result) {
	extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	queue_priority: f32 = 1.0
	queue_info := vk.DeviceQueueCreateInfo{sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = graphics_family, queueCount = 1, pQueuePriorities = &queue_priority}
	features_local := device_features
	create_info := vk.DeviceCreateInfo{sType = .DEVICE_CREATE_INFO, queueCreateInfoCount = 1, pQueueCreateInfos = &queue_info, enabledExtensionCount = u32(len(extensions)), ppEnabledExtensionNames = raw_data(extensions), pEnabledFeatures = &features_local}
	device: vk.Device
	result := vk.CreateDevice(physical_device, &create_info, nil, &device)
	return device, result
}

//  MAIN builds everything the demo's pipeline will need to bind - mesh SSBO + texture + uniform buffers, wrapped into descriptor sets

main :: proc() {
	glfw.Init()
	defer glfw.Terminate()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(800, 600, "Vulkan Mesh + Descriptor Sets", nil, nil)
	defer glfw.DestroyWindow(window)
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	instance := create_instance()
	defer vk.DestroyInstance(instance, nil)

	surface: vk.SurfaceKHR
	vk_check(glfw.CreateWindowSurface(instance, window, nil, &surface), "creating window surface")
	defer vk.DestroySurfaceKHR(instance, surface, nil)

	physical_device, found := find_suitable_physical_device(instance, proc(device: vk.PhysicalDevice) -> bool {
		family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
		return family_count > 0
	})
	if !found { fmt.println("no suitable gpu found"); return }

	graphics_family := find_queue_families(physical_device, {.GRAPHICS})

	// the wireframe geometry shader needs this optional gpu feature switched on
	supported: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(physical_device, &supported)
	if !supported.geometryShader { fmt.println("this gpu has no geometry shader support"); return }
	device_features: vk.PhysicalDeviceFeatures
	device_features.geometryShader = true

	device, dev_result := create_device(physical_device, device_features, graphics_family)
	vk_check(dev_result, "creating logical device")
	defer vk.DestroyDevice(device, nil)
	vk.load_proc_addresses(device)

	graphics_queue: vk.Queue
	vk.GetDeviceQueue(device, graphics_family, 0, &graphics_queue)

	pool_info := vk.CommandPoolCreateInfo{sType = .COMMAND_POOL_CREATE_INFO, queueFamilyIndex = graphics_family}
	command_pool: vk.CommandPool
	vk_check(vk.CreateCommandPool(device, &pool_info, nil, &command_pool), "creating command pool")
	defer vk.DestroyCommandPool(device, command_pool, nil)

	state: VulkanState
	defer delete(state.uniform_buffers)
	defer delete(state.uniform_buffers_memory)
	defer delete(state.descriptor_sets)

	// --- texture (binding 3) --- EDIT THESE PATHS to real files on your system
	texture_image, texture_memory, tex_ok := create_texture_image(device, physical_device, command_pool, graphics_queue, "rubber_duck/DuckCM.png")
	if !tex_ok { fmt.println("failed to load texture image"); return }
	defer { vk.DestroyImage(device, texture_image, nil); vk.FreeMemory(device, texture_memory, nil) }

	view_ok: bool
	state.texture_view, view_ok = create_image_view(device, texture_image, .R8G8B8A8_UNORM, {.COLOR})
	if !view_ok { fmt.println("failed to create texture image view"); return }
	defer vk.DestroyImageView(device, state.texture_view, nil)

	sampler_ok: bool
	state.texture_sampler, sampler_ok = create_texture_sampler(device)
	if !sampler_ok { fmt.println("failed to create texture sampler"); return }
	defer vk.DestroySampler(device, state.texture_sampler, nil)

	// --- mesh vertices + indices in one SSBO (bindings 1 and 2) ---
	mesh_ok: bool
	state.mesh, mesh_ok = create_textured_vertex_buffer(device, physical_device, command_pool, graphics_queue, "rubber_duck/scene.gltf")
	if !mesh_ok { fmt.println("failed to create mesh buffer"); return }
	defer destroy_buffer(device, state.mesh.buffer, state.mesh.memory)

	// --- uniform buffers, one per swapchain image (binding 0) ---
	if !create_uniform_buffers(device, physical_device, &state, IMAGE_COUNT) { fmt.println("failed to create uniform buffers"); return }
	defer for i in 0 ..< len(state.uniform_buffers) {
		destroy_buffer(device, state.uniform_buffers[i], state.uniform_buffers_memory[i])
	}

	// --- descriptor pool -> layout -> sets -> update ---
	pool_ok: bool
	// 1 uniform buffer, 2 storage buffers (vertices + indices), 1 texture per set
	state.descriptor_pool, pool_ok = create_descriptor_pool(device, IMAGE_COUNT, 1, 2, 1)
	if !pool_ok { fmt.println("failed to create descriptor pool"); return }
	defer vk.DestroyDescriptorPool(device, state.descriptor_pool, nil) // also frees every set allocated from it

	layout_ok: bool
	state.descriptor_set_layout, layout_ok = create_descriptor_set_layout(device)
	if !layout_ok { fmt.println("failed to create descriptor set layout"); return }
	defer vk.DestroyDescriptorSetLayout(device, state.descriptor_set_layout, nil)

	if !allocate_descriptor_sets(device, &state, IMAGE_COUNT) { fmt.println("failed to allocate descriptor sets"); return }
	update_descriptor_sets(device, &state, IMAGE_COUNT)

	fmt.println("mesh loaded, texture ready, and", len(state.descriptor_sets), "descriptor sets created and updated!")
}

