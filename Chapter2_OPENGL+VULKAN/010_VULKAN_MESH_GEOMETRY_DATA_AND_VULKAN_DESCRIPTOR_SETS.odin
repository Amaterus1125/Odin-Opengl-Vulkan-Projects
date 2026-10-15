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


