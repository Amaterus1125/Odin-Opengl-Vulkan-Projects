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
create_textured_vertex_buffer :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	graphics_queue: vk.Queue,
	filename: cstring, // "rubber_duck/scene.gltf"
) -> (mesh: MeshBuffer, ok: bool) {

// step 1 - load the model with cgltf (to do as the smae thing as Assimp like in CPP) parse_file reads the .gltf text, load_buffers then reads Duck0.bin, which holds the actual vertex data and sits next to the .gltf file.
options: cgltf.options
data, parse_result := cgltf.parse_file(options, filename)
if parse_result != .success {
fmt.println("Unable to load", filename)
return {}, false
	}
defer cgltf.free(data)
if cgltf.load_buffers(options, data, filename) != .success { return {}, false }

// like the book, use only the first primitive of the first mesh
prim := data.meshes[0].primitives[0]

// a glTF primitive lists its data as "attributes" (position, texcoord and many more) and then Find the position one and the texture coordinate one.
pos_acc, tc_acc: ^cgltf.accessor
for attr in prim.attributes {
#partial switch attr.type {
case .position: pos_acc = attr.data
case .texcoord: tc_acc = attr.data
		}
	}
	if pos_acc == nil { return {}, false }

	// unpack the attributes into plain float arrays
	count := int(pos_acc.count)
	positions := make([]f32, count * 3)
	texcoords := make([]f32, count * 2) // stays zeros if the model has no UVs
	defer delete(positions)
	defer delete(texcoords)
	_ = cgltf.accessor_unpack_floats(pos_acc, raw_data(positions), uint(count * 3))
	if tc_acc != nil { _ = cgltf.accessor_unpack_floats(tc_acc, raw_data(texcoords), uint(count * 2)) }

// build the vertex list. y and z are swapped as always
// vec3(v.x, v.z, v.y)
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

	// step 2 -  pack vertices + indices into one staging buffer
	// A staging buffer is plain CPU-visible memory we can write to directly.
	// The fast GPU-only buffer can't be written by the CPU, so we copy through it.
	vertex_bytes := vk.DeviceSize(size_of(VertexData) * count)
	index_bytes  := vk.DeviceSize(size_of(u32) * index_count)

/* The index section gets its own descriptor later, and Vulkan requires that descriptor's offset to be a multiple of the GPU's minStorageBufferOffsetAlignment (up to 256). 
20-byte vertices don't guarantee that, so we pad the offset up to 256 and skip many problems which can occur */
	ALIGN :: 256
	index_offset := (vertex_bytes + ALIGN - 1) &~ vk.DeviceSize(ALIGN - 1)
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
	mem.zero(mapped, int(buffer_size))
	mem.copy(mapped, raw_data(vertices), int(vertex_bytes))
	mem.copy(rawptr(uintptr(mapped) + uintptr(index_offset)), raw_data(indices), int(index_bytes))
	vk.UnmapMemory(device, staging_memory)

	// the real buffer, in GPU-only memory. TRANSFER_DST lets the copy write into it; STORAGE_BUFFER lets a shader read it.
	mesh.buffer, mesh.memory, ok = create_buffer(
	device, physical_device, buffer_size,
	{.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL},
	)
	if !ok { return {}, false }

	// step 3: copy staging to thee GPU buffer
copy_buffer(device, command_pool, graphics_queue, staging_buffer, mesh.buffer, buffer_size)
mesh.vertex_size  = vertex_bytes
mesh.index_offset = index_offset
mesh.index_size   = index_bytes
return mesh, true
}


// PART 2: DESCRIPTOR SETS
// Descriptor sets can't be created directly and they are handed out by a pool the pool must be big enough for everything we'll allocate, and we make one set per swapchain image, so every count is multiplied by image_count.
create_descriptor_pool :: proc(
device: vk.Device,
image_count: u32,
uniform_buffer_count, storage_buffer_count, sampler_count: u32, ) -> (pool: vk.DescriptorPool, ok: bool) {
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
sType = .DESCRIPTOR_POOL_CREATE_INFO,
maxSets = image_count, // one set per swapchain image
poolSizeCount = u32(len(pool_sizes)),
pPoolSizes = raw_data(pool_sizes),
}
result := vk.CreateDescriptorPool(device, &pool_info, nil, &pool)
return pool, result == .SUCCESS
}
descriptor_set_layout_binding :: proc(binding: u32, kind: vk.DescriptorType, stages: vk.ShaderStageFlags) -> vk.DescriptorSetLayoutBinding {
return {binding = binding, descriptorType = kind, descriptorCount = 1, stageFlags = stages}
}

// steps 2 to 8 -  layout, allocate, fill in,`uniform_buffers` is one uniform buffer per swapchain image.
create_descriptor_set :: proc(
device: vk.Device,
descriptor_pool: vk.DescriptorPool,
uniform_buffers: []vk.Buffer,
ubo_size: vk.DeviceSize, // pass size_of(UniformBuffer)
mesh: MeshBuffer,
texture_sampler: vk.Sampler,
texture_view: vk.ImageView,
) -> (layout: vk.DescriptorSetLayout, sets: []vk.DescriptorSet, ok: bool) {
	image_count := len(uniform_buffers)
// step 2-3 - the LAYOUT describes what a set contains. These 4 binding numbers MUST match layout(binding = N) in the shaders (like in last file 010)
bindings := [4]vk.DescriptorSetLayoutBinding{
descriptor_set_layout_binding(0, .UNIFORM_BUFFER, {.VERTEX}),           // mvp matrix
descriptor_set_layout_binding(1, .STORAGE_BUFFER, {.VERTEX}),           // vertices
descriptor_set_layout_binding(2, .STORAGE_BUFFER, {.VERTEX}),           // indices
descriptor_set_layout_binding(3, .COMBINED_IMAGE_SAMPLER, {.FRAGMENT}), // texture
}
layout_info := vk.DescriptorSetLayoutCreateInfo{
sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
bindingCount = u32(len(bindings)),
pBindings = &bindings[0],
}
if vk.CreateDescriptorSetLayout(device, &layout_info, nil, &layout) != .SUCCESS {
return {}, nil, false
}

// step 4 - ALLOCATE one set per swapchain image, all using that layout
layouts := make([]vk.DescriptorSetLayout, image_count)
defer delete(layouts)
for i in 0 ..< image_count { layouts[i] = layout }

alloc_info := vk.DescriptorSetAllocateInfo{
sType  = .DESCRIPTOR_SET_ALLOCATE_INFO,
descriptorPool  = descriptor_pool,
descriptorSetCount = u32(image_count),
pSetLayouts = raw_data(layouts),
}
sets = make([]vk.DescriptorSet, image_count)
if vk.AllocateDescriptorSets(device, &alloc_info, raw_data(sets)) != .SUCCESS {
return layout, sets, false
}

// step 5-8 - the sets exist but are empty. Point each binding at a real resource and this is vulkan's version of glBindBuffer / glBindTexture (already discussed in 010) except it's done once here instead of every frame, so you can't just swap the texture between frames.
for i in 0 ..< image_count {
ubo_info      := vk.DescriptorBufferInfo{buffer = uniform_buffers[i], offset = 0, range = ubo_size}
vertices_info := vk.DescriptorBufferInfo{buffer = mesh.buffer, offset = 0, range = mesh.vertex_size}
indices_info  := vk.DescriptorBufferInfo{buffer = mesh.buffer, offset = mesh.index_offset, range = mesh.index_size}
image_info    := vk.DescriptorImageInfo{sampler = texture_sampler, imageView = texture_view, imageLayout = .SHADER_READ_ONLY_OPTIMAL}
// one write per binding like we did in 010 file (last file)
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
