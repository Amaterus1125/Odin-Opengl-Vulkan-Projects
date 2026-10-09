// will be using the rubber_duck asset here 


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


