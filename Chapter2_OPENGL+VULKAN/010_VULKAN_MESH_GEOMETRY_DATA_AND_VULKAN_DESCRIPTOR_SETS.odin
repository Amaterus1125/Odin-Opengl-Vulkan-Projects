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

/* size_of(VertexData) == 20 bytes , tightly packed , that matches the struct VertexData { float x , y, z ; float u , v} in the vertex shader 
 * because SSBO's use std430 layout , which does not pad this struct , .obj indices are 1- based , and negative numbers count backwards from the end of the list so far ,
 * this turns either form into 0-based index (or -1 is it's missing or invalid) */ 

resolve_obj_index :: proc(i , count : int) -> int { 
if i >0 {return i -1 }
if i < 0 {return count +1 }
return -1 
}

load_obj :: proc(filename : string) -> (vertices : [dynamic]VertexData , indices: [dynamic]u32 , ok : bool ){

// note - in recent odin versions , this returns an error value and not a bool 
file_data , read_err := os.read_entire_file(filename , context.allocator) 
if read_err != nil{return {} ,{} , false}
defer delete(file_data)
positions : [dynamic][3]f32 
texcoords : [dynamic][2]f32 
defer delete(positions)
defer delete(texcoords)

// an .obj face corner is a (position index , texcoord index ) pair , two corners with the same pair are the same vertex , so we remember 
// which pairs we have already emitted , that's what makes the mesh indexed instead of three brand new vertices every triangle 
unique : map[[2]int]u32 
defer delete(unique)
}
