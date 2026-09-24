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
   
   s size_t maps to Odin's uint (both are pointer-sized), and a T - const T* maps to Odin's multi-pointer [^]T - a raw pointer with no built-in length, exactly what these C arrays are.
   
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
	meshopt_generateVertexRemap :: proc(destination: [^]u32, indices: [^]u32, index_count: uint, vertices: rawptr, vertex_count: uint, vertex_size: uint) -> uint ---

	  //builds the actual deduplicated vertex buffer using a remap table from the function above 
	meshopt_remapVertexBuffer :: proc(destination: rawptr, vertices: rawptr, vertex_count: uint, vertex_size: uint, remap: [^]u32) ---

	 //builds a fresh index buffer through the same remap table , pass indices = nil , here too when you don't have real indices yet - it generates the implicit 0,1,2,3 sequences and remap 
	meshopt_remapIndexBuffer :: proc(destination: [^]u32, indices: [^]u32, index_count: uint, remap: [^]u32) ---

	// Reorders TRIANGLES (not vertices) so nearby triangles in the index buffer tend to reuse vertices the GPU's small post-transform vertex cache still has warm. Doesn't change what gets drawn, only the order indices are stored in.
	meshopt_optimizeVertexCache :: proc(destination: [^]u32, indices: [^]u32, index_count: uint, vertex_count: uint) ---

	// Reorders the VERTEX buffer itself to match the access order set by
	// the triangle order above (and rewrites indices to match) - good for
	// cache locality when the vertex shader reads it.
	meshopt_optimizeVertexFetch :: proc(destination: rawptr, indices: [^]u32, index_count: uint, vertices: rawptr, vertex_count: uint, vertex_size: uint) -> uint ---
}

PerFrameData :: struct {
  mvp: matrix[4,4]f32,
}

main :: proc() {
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
options : cgltf.options // leave this zeroed/default , we don't need any specific settings 
data , parse_result := cgltf.parse_file(options, "Avocado.gltf")
if parse_result != .success {
       fmt.println("FAILED TO FIND THE PARSED GLTF FILE:" , parse_result)
       return
}
defer cgltf.free(data)  // free the loaded model data once main() ends 

/* Parsing only reads the JSON structure of the file , the actual raw vertex numbers and fragment shader lives 
in a seperate binary buffers that will still nees to load in as a second step */

load_result := cgltf.load_buffers(options , data , "Avocado.gltf")
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
this flattens everything into one long triangle list and uses a manual face flattening loop  */
index_count := prim.indices.count 
for i in 0 ..< index_count {
    idx := cgltf.accessor_read_index(prim.indices , i) 
    v : [3]f32 
    ok := cgltf.accessor_read_float(pos_accessor , idx , &v[0] , 3)
    if !ok {
       continue    //skip this vertex if reading it somehow failed 
 }
  append(&positions , [3]f32{v.x,v.y,v.z})
}
}

/* MESHOPTIMIZER - dedupe + optimize before this ever touches the GPU, WHERE this goes: right here, after `positions` is built and BEFORE the
 "UPLOAD THE POSITIONS TO THE GPU" section below - MeshOptimizer is a pure CPU-side pass over plain arrays, it doesn't know or care that the data came from cgltf, it just wants a vertex buffer (and optionally an index
 buffer) to rearrange. WHY it's needed here specifically: the loop above just finished walking prim.indices and pushing a FRESH COPY of each vertex's xyz every time -
 so if two triangles share an edge, that shared vertex now exists TWICE in positions (once per triangle corner that touches it). That's wasted
 GPU memory and wasted vertex-shader work for no reason. MeshOptimizer's generateVertexRemap step below finds those duplicates and gives you both a deduplicated vertex buffer AND a real index buffer back, which also
 means switching the draw call from gl.DrawArrays to gl.DrawElements. */

index_count := uint(len(positions))

// find duplicates indices = nil tells MeshOptimizer "this vertex buffer is unindexed" (see the WHY above) - it treats every position as its own separate corner and figures out which ones are actually identical. Returns how many UNIQUE vertices are left.
remap := make([]u32, index_count)
defer delete(remap)
vertex_count := meshopt_generateVertexRemap(
	raw_data(remap), nil, index_count,
	raw_data(positions), index_count, size_of([3]f32),
)

// build the deduplicated vertex buffer using that remap table.
remapped_positions := make([][3]f32, vertex_count)
defer delete(remapped_positions)
meshopt_remapVertexBuffer(
	raw_data(remapped_positions), raw_data(positions), index_count, size_of([3]f32),
	raw_data(remap),
)

// Step 3 - build a real index buffer to go with it. `indices = nil` again means "we don't have one yet, generate the implicit 0,1,2,3... sequence (which matches the order `positions` is already in) and remap THAT."
indices := make([]u32, index_count)
defer delete(indices)
meshopt_remapIndexBuffer(raw_data(indices), nil, index_count, raw_data(remap))

// reorder triangles for the GPU's post-transform vertex cache. Pure reordering, doesn't change what gets drawn.
meshopt_optimizeVertexCache(raw_data(indices), raw_data(indices), index_count, vertex_count)

// now that triangle order is settled, reorder the vertex buffer itself to match how it's actually accessed (indices get rewritten to match automatically).
meshopt_optimizeVertexFetch(
	raw_data(remapped_positions), raw_data(indices), index_count,
	raw_data(remapped_positions), vertex_count, size_of([3]f32),
)

fmt.println("MESHOPTIMIZER: deduped", len(positions), "->", vertex_count, "unique vertices, ", index_count, "indices")

// UPLOAD THE POSITIONS TO THE GPU 
num_indices := i32(index_count)
fmt.println("LOADED" , vertex_count, "VERTICES")

vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(remapped_positions) * size_of([3]f32), raw_data(remapped_positions), gl.STATIC_DRAW)

	// NEW: an index buffer (EBO) to go with the deduplicated vertex buffer -
	// before MeshOptimizer we had no index buffer at all, since `positions`
	// was unindexed and we drew with gl.DrawArrays. Binding this while `vao`
	// is bound records it as this VAO's element array buffer.
	ibo: u32
	gl.GenBuffers(1, &ibo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of([3]f32), 0)

	// vertex and fragment SHADERS - plain position only, driven by an MVP matrix
	vertex_src := `#version 460 core
layout (location = 0) in vec3 a_pos;
layout (std140, binding = 0) uniform PerFrameData { mat4 MVP; };
void main() {
	gl_Position = MVP * vec4(a_pos, 1.0);
}`

	fragment_src := `#version 460 core
layout (location = 1) uniform vec4 u_color;
out vec4 out_color;
void main() {
	out_color = u_color; 
}`

	vs := gl.CreateShader(gl.VERTEX_SHADER)
	src1 := cstring(raw_data(vertex_src))
	gl.ShaderSource(vs, 1, &src1, nil)
	gl.CompileShader(vs)

	fs := gl.CreateShader(gl.FRAGMENT_SHADER)
	src2 := cstring(raw_data(fragment_src))
	gl.ShaderSource(fs, 1, &src2, nil)
	gl.CompileShader(fs)

	program := gl.CreateProgram()
	gl.AttachShader(program, vs)
	gl.AttachShader(program, fs)
	gl.LinkProgram(program)
	gl.DeleteShader(vs)
	gl.DeleteShader(fs)

	// a small buffer that holds just our MVP matrix, shared with the shader every frame
	per_frame_buf: u32
	gl.CreateBuffers(1, &per_frame_buf)
	gl.NamedBufferStorage(per_frame_buf, size_of(PerFrameData), nil, gl.DYNAMIC_STORAGE_BIT)
	gl.BindBufferRange(gl.UNIFORM_BUFFER, 0, per_frame_buf, 0, size_of(PerFrameData))

	for !glfw.WindowShouldClose(window) {
		width, height := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, width, height)
		gl.ClearColor(0.1, 0.1, 0.1, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		aspect := f32(width) / f32(height)
		p := linalg.matrix4_perspective_f32(linalg.to_radians(f32(60.0)), aspect, 0.1, 100.0)
		view := linalg.matrix4_translate_f32({0.0, -3.0, -12.0}) // pull the camera back so the model is in view
		
        // to make it spin on its own hehe
        time := f32(glfw.GetTime())
		model := linalg.matrix4_rotate_f32(time, {0.0, 1.0, 0.0})
		mvp := p * view * model

		frame_data := PerFrameData{mvp = mvp}
		gl.NamedBufferSubData(per_frame_buf, 0, size_of(PerFrameData), &frame_data)

		gl.UseProgram(program)
		gl.BindVertexArray(vao)

		// same two-pass trick as the book: solid fill, then wireframe on top
		// NOTE: DrawArrays -> DrawElements, since we now have a real index
		// buffer (ibo) instead of one duplicated vertex per triangle corner.
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
		gl.Uniform4f(1, 1.0, 0.7, 0.2, 1.0) // Set solid color to yellow
		gl.DrawElements(gl.TRIANGLES, num_indices, gl.UNSIGNED_INT, nil)

		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
		gl.Uniform4f(1, 0.0, 0.0, 0.0, 1.0) // Set wireframe color to black
		gl.DrawElements(gl.TRIANGLES, num_indices, gl.UNSIGNED_INT, nil)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}

	gl.DeleteBuffers(1, &per_frame_buf)
	gl.DeleteBuffers(1, &vbo)
	gl.DeleteBuffers(1, &ibo)
	gl.DeleteVertexArrays(1, &vao)
	gl.DeleteProgram(program)
}
