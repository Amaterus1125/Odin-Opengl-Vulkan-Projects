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


