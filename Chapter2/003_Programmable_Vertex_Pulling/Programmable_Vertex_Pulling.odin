//THE NORMAL IMPORTS FOR EVERY FILE 

package main

import "core:fmt"
import "core:math/linalg"

import "vendor:glfw"
import gl "vendor:OpenGL"
import cgltf "vendor:cgltf"
import stbi "vendor:stb/image"

// PROGRAMMABLE VERTEX PULLING - 
/* 
Normally opengl feeds vertex data to our shader sutomatically , we set up VAO that says "position is 3 floats starting here, uv is 2 floats starting here" and the GPU hands your shader the right numbers for each vertex without us doing anything,

PVP throws that automatic part away and instead we hand the shader a big raw buffer of number directly as an SSBO - shader storage buffer object, ssbo is just a big array that shader can read from manually, and let the shader look up whatever it needs itself,
using gl_VertexID (a vertex no. which gpu provides to a vertex itself) as an index into that array 

Doing indexing by hand helps us later on to cram multiple different meshes into one giant buffer and drawing them all on a single draw call, without opengl needing to stop and switch buffers/ VAO between each mesh, fewer draw calls will also help in 
CPU spending less time telling the GPU to draw something, this is just step 1 where we manually indexing a single mesh so to see how the mechanism works before combining multiple meshes later  */

PerFrameData :: struct { 
 mvp : matrix[4,4]f32,
}

// this has to exactly match the shader's "Vertex" struct below, including using separate floats instead of a vec3
VertexData:struct { 
 pos:[3]f32,
 tc : [3]f32,
}


//  CAMERA STATE (added so you can fly around instead of being stuck staring from inside the duck)
camera_pos:   [3]f32 = {0, 0, 5}
camera_front: [3]f32 = {0, 0, -1}
camera_up:    [3]f32 = {0, 1, 0}
camera_speed: f32 = 3.0
last_frame_time: f32 = 0

update_camera :: proc(window: glfw.WindowHandle, dt: f32) {
	move := camera_speed * dt
	right := linalg.normalize(linalg.cross(camera_front, camera_up))

	if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS { camera_pos += camera_front * move }
	if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS { camera_pos -= camera_front * move }
	if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS { camera_pos -= right * move }
	if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS { camera_pos += right * move }
	if glfw.GetKey(window, glfw.KEY_SPACE) == glfw.PRESS { camera_pos += camera_up * move }
	if glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS { camera_pos -= camera_up * move }
}




vertex_src := `#version 460 core 
layout(std140 , binding = 0) uniform PerFramData { 
 uniform mat4 MVP;
};

/* this struct layout must match the VertexData on the odin side exactly , we use float[3] / float[2] instead of vec3/ vec2 here on purpose,as GLSL silently pads a vec3 to take up same space as a vec4 (16 bytes) instead a buffer like this ,
which would make our odin struct and the shader struct diagree about where each vertex data actually start, plain floats have no such padding , so both sides agree */

struct Vertex { float p[3] ; float tc[2]; };

//binding = 1 here is our raw vertex data buffer, readonly just means that the shader can only read from it and never write back to it 

layout(std430, binding = 1) readonly buffer Vertices { Vertex in_Vertices[]; };

vec3 getPosition(int i) { return vec3(in_Vertices[i].p[0], in_Vertices[i].p[1], in_Vertices[i].p[2]); }
vec2 getTexCoord(int i) { return vec2(in_Vertices[i].tc[0], in_Vertices[i].tc[1]); }

layout (loaction =0) out vec2 uv;
void main() { 
// gl_VertexID normally just counts 0 ,1,2,3 but since our VAO has an index buffer attached , opengl automatically feels gl_VertexID the actual index values insread , so this naturally puls the right vertex , reused across shared corners , same as normal indexed rendering would 
vec3 pos = getPosition(gl_VertexID);
gl_position = MVP * vec4(pos, 1.0) ;
uv = getTexCoord(gl_VertexID) ;
}`

fragment_src := `#version 460 core 
layout(location =0) in vec2 uv;
layout(location =0) out vec4 out_FragColor;
layout(location =0) uniform sampler2D texture0;
void main() { 
  out_FragColor = texture(texture0 , uv);
}`

/* writing the shader wrappers (same ones from 007_SHADER_LOADER.odin, copied in here so this file runs standalone with `odin run ... -file`. If you're
running these as a folder instead with `odin run .`, you can delete this block and just keep the imports -- Odin will use the versions
from 007_SHADER_LOADER.odin automatically since they're in the same package) */

Shader :: struct { 
type: u32,
handle : u32,
}

create_shader :: proc(type: u32 , text: string) -> Shader { 
 handle := gl.CreateShader(type)
c_text := cstring(raw_data(text)) 
gl.ShaderSource(handle , 1, &c_text , nil) 
gl.CompileShader(handle) 

buffer : [8192]u8 
length : i32 
gl.GetShaderInfoLog( handle , size_of(buffer) , &length , raw_data(buffer[:])) 
if length > 0 {
 fmt.println(string(buffer[:length])) 
} 
return Shader{type , handle}
}

destroy_shader :: proc(s : ^Shader) { 
 gl.DeleteShader(s.handle) 
} 

Program :: struct { 
handle : u32 ,
} 

create_program :: proc(shaders: ..Shader) -> Program { 
 handle := gl.CreateProgram() 
 for s in shaders { 
 gl.AttachShader(handle , s.handle) 
}
gl.LinkProgram(handle) 

buffer: [8192]u8 
length : i32 
gl.GetProgramInfoLog(handle , size_of(buffer) , &length , raw_data(buffer[:]))
if length > 0 {
 fmt.println(string(buffer[:length])) 
}
return Program{handle}
}

destroy_program :: proc(p: ^Program) { 
 gl.DeleteProgram(p.handle)
}

use_program :: proc(p : ^Program) { 
gl.UseProgram(p.handle) 
} 

main :: proc() { 
glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(800, 600, "THE ODIN EYE", nil, nil)
	glfw.MakeContextCurrent(window)
	gl.load_up_to(4, 6, glfw.gl_set_proc_address)
	gl.Enable(gl.DEPTH_TEST)

// EDIT THESE 2 PATHS to point at your own duck model files
	DUCK_GLTF_PATH :: "rubber_duck/scene.gltf"
	DUCK_TEXTURE_PATH :: "rubber_duck/DuckCM.png"

//loading the model 
options: cgltf.options
	data, parse_result := cgltf.parse_file(options, DUCK_GLTF_PATH)
	if parse_result != .success {
		fmt.println("failed to parse duck gltf:", parse_result)
		return
	}
	defer cgltf.free(data)
	load_result := cgltf.load_buffers(options, data, DUCK_GLTF_PATH)
	if load_result != .success {
		fmt.println("failed to load duck buffers: sed", load_result)
		return
	}

mesh := data.meshes[0]
prim := mesh.primitives[0] 

pos_accessor , uv_accessor: ^cgltf.accessor
for attr in prim.attributes {
#partial switch attr.type { 
case .position: pos_accessor = attr.data
case .texcoord: uv_accessor = attr.data
}
}

//build our array of VertexData, one entry per vertex -- matches the vertices.push_back({pos , tc}) loop 
vertex_count := int(pos_accessor.count)
vertices := make([]VertexData , vertex_count) 
for i in 0 ..< vertex_count { 
 p , uv: [3]f32 
 _ = cgltf.accessor_read_float(pos_accessor , uint(i) , &p[0] , 3)
 if uv_accessor != nil { 
 _ = cgltf.accessor_read_float(uv_accessor , uint(i) , &uv[0] , 2)
} 
// y and z are swapped here and same as our earlier duck examples , gltf and this engine does not agree on which axis is "up" so we flip them to orient the model correctly 
vertices[i] = VertexData{pos = { p.x , p.z , p.y} , tc = { uv.x , uv.y} }
}

index_count := int(prim.indices.count)
indices := male([]u32 , index_count) 
for i in 0 ..< index_count { 
 indices[i] = u32(cgltf.acessor_read_index(prim.indices , uint(i)))
}

//upload both the buffers 
data_indices: u32
	gl.CreateBuffers(1, &data_indices)
	gl.NamedBufferStorage(data_indices, len(indices) * size_of(u32), raw_data(indices), 0)

	data_vertices: u32
	gl.CreateBuffers(1, &data_vertices)
	gl.NamedBufferStorage(data_vertices, len(vertices) * size_of(VertexData), raw_data(vertices), 0)

//the VAO only knows about the index buffer , there are no vertex attributes set up at all , since the shader is pulling vertex data manually instead 

vao: u32
gl.CreateVertexArrays(1, &vao)
gl.BindVertexArray(vao)
gl.VertexArrayElementBuffer(vao, data_indices)
// bind our raw vertex buffer to binding point 1, matching the shader's "layout(std430, binding = 1)" declaration
gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, data_vertices)

// loading the texture  

w, h, comp: i32
img := stbi.load(DUCK_TEXTURE_PATH, &w, &h, &comp, 3)
if img == nil {
fmt.println("failed to load duck texture : sed")
return
}
defer stbi.image_free(img)

//texture is 2D- mostly DuckCM.png
tex: u32
gl.CreateTextures(gl.TEXTURE_2D, 1, &tex)
gl.TextureParameteri(tex, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
gl.TextureParameteri(tex, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
gl.TextureStorage2D(tex, 1, gl.RGB8, w, h)
gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
gl.TextureSubImage2D(tex, 0, 0, 0, w, h, gl.RGB, gl.UNSIGNED_BYTE, img)
gl.BindTextures(0, 1, &tex)




