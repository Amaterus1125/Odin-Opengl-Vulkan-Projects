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
  buffer : vk.Buffer , 
  memory : vk.DeviceMemory , 
  vertex_size : vk.DeviceSize  , //bytes of vertex data , starts at offset 0 
  index_offset : vk.DeviceSize , // where the index data starts 
  index_size : vk.DeviceSize , // bytes of index data
}

align_up 
