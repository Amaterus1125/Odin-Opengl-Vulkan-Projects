// the basic imports we have to do everytime

package main

import "core:fmt"
import "core"math/linalg"
import "vendor:glfw"
import gl "vendor:OpenGL"
import cgltf "vendor:cgltf"

/* What this this file do - In cpp you use Assimp to load a 3d model file , assimp is a big c++ library and has no odin versions 
but since the example we are taking is gltf model , we can use cgltf instead which is an already build odin library 
and precompiled for windows OS */

//The big idea is to open a 3d model file , pull out just the vertex position and upload them to the gpu and draw them.

PerFrameData :: struct {
  mvp: matrix[4,4]f32,
}

main :: proc{} {
      glfw.Init() 
      defer glfw.Terminate() 
      glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	   glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	   glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	   window := glfw.CreateWindow(800, 600, "glTF Model", nil, nil)
	   glfw.MakeContextCurrent(window)
	   gl.load_up_to(4, 6, glfw.gl_set_proc_address)
	   gl.Enable(gl.DEPTH_TEST)

// loading the model file 
options := cgltf.options // leave this zeroed/default , we don't need any specific settings 
data , parse_result := cgltf.parse_file(options, "data/Assets/Avocado.gltf")
if parse_result != .success {
       fmt.println("FAILED TO FIND THE PARSED GLTF FILE:" , parse_result)
       return
}
defer cgltf.free(data)  // free the loaded model data once main() ends 

/* Parsing only reads the JSON structure of the file , the actual raw vertex numbers and fragment shader lives 
in a seperate binary buffers that will still nees to load in as a second step */

load_result := cgltf.load_buffers(options , data , "data/Assets/Avocado.gltf")
if load_result != .success {
   fmt.println("FAILED TO LOAD THE GLTF BUFFERS:", load_result)
   return
}

// Pull out just the vertex positions
positions : [dynamic][3]f32
defer delete(positions)

mesh := data.meshes[0] //just grab the first mesh , like the only first mesh it can find 
prim := mesh.primitives[0] // and its first primitive attributes 

//find the position attribute among this primitive's attributes 
pos_accessor : ^cgltf.accessor
for attr in prim.attributes {
     if attr.type == .position { 
           pos_accessor = attr.data
} }

if prim.indices != nil {
 /* the model must have an index list ( most of them do) walk through it and for each index look up that vertex actual xyz position 
this flattens everything into one long triangle list and uses a manual face flattening loop 
imdex_count := prim.indices.count 
for i in 0 ..< index_count {
    idx := cgltf.accessor_read_index(prim.indices , i) 
    v : [3]f32 
    ok := cgltf.accessor_read_float(pos_accessor , idx , &v[0] , 3)
    if !ok {
       countinue    //skip this vertex if reading it somehow failed 
 }
  append(&positions , [3]f32{v.x,v.z,v.y})
}



