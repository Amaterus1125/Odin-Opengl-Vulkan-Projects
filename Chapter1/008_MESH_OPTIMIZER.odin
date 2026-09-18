// PLS PUT THE BIN FILE WITH THE GLTF MODEL FILE FOR IT TO LOAD , BC THE BIN FILE CONTAINS THE JSON DATA FOR THE BUFFER
//ALSO THIS IS THE CODE WITH MESH OPTIMIZER FROM 005_LOAD_GLTF_MODEL (may look the exact same as before but the meshes are optimized)

package main

import "core:fmt"
import "core:math/linalg"
import "vendor:glfw"
import gl "vendor:OpenGL"
import cgltf "vendor:cgltf"

/* What this this file do - In cpp you use Assimp to load a 3d model file , assimp is a big c++ library and has no odin versions 
but since the example we are taking is gltf model , we can use cgltf instead which is an already build odin library 
and precompiled for windows OS */
//The big idea is to open a 3d model file , pull out just the vertex position and upload them to the gpu and draw them.

/* MESHOPTIMIZER BINDINGS AND WHAT DOES IT DO - 
   Meshoptimizer on github has its header which is already c-compatible, the library internals are C++ but every public function 
   is warped in extern C , so we can foreign import striaght into the compiled library and declare the handful of functions we need ourselves without the bridge being required 
   
   s size_t maps to Odin's uint (both are pointer-sized), and a T*/const T* maps to Odin's multi-pointer [^]T - a raw pointer with no built-in length, exactly what these C arrays are.
   
ONE-TIME BUILD STEP: compile meshoptimizer into a static lib (it ships its own CMakeLists.txt, target name `meshoptimizer`):
     git clone https://github.com/zeux/meshoptimizer
     cmake -S meshoptimizer -B build -G "Visual Studio 18 2026" -A x64
     cmake --build build --config Release
     build/Release/meshoptimizer.lib (point foreign import at that path)
*/ 

foreign import meshopt "meshoptimizer/build/Release/meshoptimizer.lib"
foreign meshopt {
    /* finds the duplicate vertices and builds a table which states about which unique slot each vertex belongs to , passes indices as nil (indices=nil) 
    and buffer is unindexed (one entry per triangle corner, duplicates and all) - exactly what positions looks like furthur down the file 
    and returns the number of unique vertices left after dedup */ 
   meshopt_remapVertexBuffer :: proc(destination : [^]u32 , indices:[^]u32 , index_count: uint , vertices:rawptr , vertex_count:uint , vertex_size:uint) -> uint ---

  //builds the actual deduplicated vertex buffer using a remap table from the function above 
  meshopt_remapVertexBuffer :: proc(destination: rawptr, vertices: rawptr, vertex_count: uint, vertex_size: uint, remap: [^]u32) ---

  //builds a fresh index buffer through the same remap table , pass indices = nil , here too when you don't have real indices yet - it generates the implicit 0,1,2,3 sequences and remap 
  meshopt_optimizeVertexCache :: proc(destination: [^]u32, indices: [^]u32, index_count: uint, vertex_count: uint) ---

 //Reorders the VERTEX BUFFER itself to match the access order set by the triangle order above (and rewrites indices to match) , good for cache locality when the vertex shader reads it 
  meshopt_optimizerVertexFetch :: proc(destination: rawptr, indices: [^]u32, index_count: uint, vertices: rawptr, vertex_count: uint, vertex_size: uint) -> uint ---
}
