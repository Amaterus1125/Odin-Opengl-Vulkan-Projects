package main

import "core:fmt"
import "core:os"
import "core:strings"

import "vendor:glfw"
import gl "vendor:OpenGL"

/* Odin does not have constructors/destructors like C++ so we can't use GLShader/GLprogram like in C++ , creating the object compiles the shader , and the object being destroyed automatically cleans the gpu resource , as odin have no destructors/constructors,
and only have structs which are just plain data, to do that in odin we will create a "create_x" function that builds something and a similar "destroy_x" function we call ourselves (right after the creation via 'defer') , so cleanup is guranteed without us having to rememebr it later */

//PART 1 - loading shader source from a file 

//reads a whole shader file off disk as one big string 
read_shader_file :: proc(file_name: string) -> string {
data, err := os.read_entire_file_from_path(file_name, context.allocator)
if err != nil {
	fmt.printfln("I/O error. Cannot open '%s'", file_name)
	return ""
	}
//now creating a BOM - Byte order marker , is 3 invisble bytes which some text editors silently stick to the start of a file , some old glsl compilers choke on it so we have strip it off id it's here 
bom := []u8{0xEF, 0xBB, 0xBF}
start := 0
if len(data) >= 3 && data[0] == bom[0] && data[1] == bom[1] && data[2] == bom[2] {
		start = 3
}

code := string(data[start:])

// handleing #include "file.glsl" directives 
/* glsl has no built in way to split shader code across multiple files, so this is a hand rolled version , find the #include and pull out the file name between < and >, load that file contents and paste it in place of the #include line */
for { 
pos := strings.index(code , "#include")
if pos == -1 (
break   //no more include lines left and we are done 
} 
p1 := strings.index(code[pos:] , "<")
p2 := strings.index(code[pos:], ">")
if p1 == -1 || p2 == -1 || p2 <= p1 { 
 fmt.printfln("Error while loading the shader program:\n%s" , code) 
 return "" 
}

p1 += pos
p2 += pos 
include_name := code[p1 + 1:p2]
include_code := read_shader_file(include_name) 

before := code[:pos] 
after := code[p2 +1:]
code = fmt.tprintf("%s%s%s" , before , include_code , after) 
} 
return code 
} 

//prints shader source with a line number in front of every line , makes it trivial to match a glsl compiler error (like error on line 12) straight back to the actual line in yr source 
print_shader_source :: proc(text:string) { 
 line := 1 
 fmt.printf("\n(%3) " , line) 
 for ch in text { 
     if ch == '\n' { 
      line += 1 
       fmt.printf("\n(%3d) ", line) 
    } else if ch == '\r' { 
   // skip - windows style line endings have this extra character , we don't want it to mess our printout 
} else { fmt.print(ch) } 
}  fmt.println() } 

//now looking at a file name extension to figure out what kind of shader it is ( vertex , fragment or any other) , avoid needing to pass the type seperately everytime we load a shader by filename 
shader_type_from_filename :: proc(file_name : string) -> u32 { 
 switch { 
case strings.has_suffix(file_name, ".vert"): return gl.VERTEX_SHADER
	case strings.has_suffix(file_name, ".frag"): return gl.FRAGMENT_SHADER
	case strings.has_suffix(file_name, ".geom"): return gl.GEOMETRY_SHADER
	case strings.has_suffix(file_name, ".tesc"): return gl.TESS_CONTROL_SHADER
	case strings.has_suffix(file_name, ".tese"): return gl.TESS_EVALUATION_SHADER
	case strings.has_suffix(file_name, ".comp"): return gl.COMPUTE_SHADER
} 
fmt.println("unknown shader file extension: sed" , file_name) 
return 0 
} 

// PART 2 - the shader wrapper 

Shader :: struct { 
  type : u32 ,
  handle : u32 ,
} 

//compile a shader from raw source text which we may already have in memeory 
create_shader :: proc(type: u32 , text: string) -> Shader { 
 handle := gl.CreateShader(type) 
c_text := cstring(raw_data(text))
gl.ShaderSource(handle, 1, &c_text, nil)
gl.CompileShader(handle)

/* now will check whether the compiler had anything to say , an empty log usually means that it compiled fine , but any actual message is worth showing , and for this project we print the source wirh line numbers 
alongside it so the error is very easy to track */

buffer : [8192]u8    //The 8192 is just the size of the stack buffer allocated to hold the shader compiler's info log (error/warning messages), 8192 - 8 kib 
length : i32 
gl.GetShaderInfoLog(handle, size_of(buffer) , &length , raw_data(buffer[:]))
if length > 0 { 
fmt.println(string(buffer[:length]))
print_shader_source(text) 
} 
return Shader{type , handle} 
} 

//compiles a shader straight from a file path and figures out the shader type from the extension and loads the source for us 
create_shader_from_file :: proc(file_name : string) -> Shader { 
type := shader_type_from_filename(file_name) 
source := read_shader_file(file_name) 
return create_shader(type, source) 
} 
// now freeing the shader gpu resources , call this with defer right after creating the shader , so it is aautomatically cleaned whenever the function surrounding it ends , this is odin standin for C++ destructors 
destroy_shader :: proc(s : ^Shader) { 
gl.DeleteShader(s.handle) 
} 

//PART - 3 - the program wrapper , the program on which the above thing will work on 

Program :: struct { 
handle : u32,
} 

// takes any number of already compiled shaders ( 2 for a normal vertex+fragment pair , or more if we are also using geometry shader and linkes them together into a usable program 
create_program :: proc(shaders: ..Shader) -> Program { 
handle := gl.CreateProgram() 
for s in shaders { 
gl.AttachShader(handle , s.handle) 
} 
gl.LinkProgram(handle) 
print_program_info_log(handle) 
return Program{handle}
} 

print_program_info_log :: proc(handle: u32) { 
buffer : [8192]u8
length: i32
gl.GetProgramInfoLog(handle, size_of(buffer), &length, raw_data(buffer[:]))
if length > 0 {
fmt.println(string(buffer[:length]))
}
}

destroy_program :: proc(p: ^Program) {
	gl.DeleteProgram(p.handle)
}

use_program :: proc(p: ^Program) {
	gl.UseProgram(p.handle)
}

// EXAMPLE PROGRAM , FOR THIS ABOVE CODE TO RUN ON SOMETHING - A SIMPLE RGB TRIANGLE 





example_usage :: proc() {
	shader_vertex := create_shader_from_file("data/shaders/chapter03/GL02.vert")
	defer destroy_shader(&shader_vertex)

	shader_geometry := create_shader_from_file("data/shaders/chapter03/GL02.geom")
	defer destroy_shader(&shader_geometry)

	shader_fragment := create_shader_from_file("data/shaders/chapter03/GL02.frag")
	defer destroy_shader(&shader_fragment)

	program := create_program(shader_vertex, shader_geometry, shader_fragment)
	defer destroy_program(&program)

	use_program(&program)
}

//using PROGRAM PIPELINES -- an alternative way of linking shaders together into one program , instead of each shader getting its own seperate mini program , we just mix-match them at draw timw , handly if we want to reuse the same vertex shader without needing a full combination of every pairing 
example_program_pipeline :: proc(vertex_src, fragment_src: string) {
	vs_c := cstring(raw_data(vertex_src))
	fs_c := cstring(raw_data(fragment_src))

	vs := gl.CreateShaderProgramv(gl.VERTEX_SHADER, 1, &vs_c)
	fs := gl.CreateShaderProgramv(gl.FRAGMENT_SHADER, 1, &fs_c)

	pipeline: u32
	gl.CreateProgramPipelines(1, &pipeline)
	gl.UseProgramStages(pipeline, gl.VERTEX_SHADER_BIT, vs)
	gl.UseProgramStages(pipeline, gl.FRAGMENT_SHADER_BIT, fs)
	gl.BindProgramPipeline(pipeline)
}

// now creating an actual runnable example 
/*  everything above this point is just a toolbox  procs meant to be reused, not run on their own. this part actually opens a window and draws a triangle USING that toolbox, so you can see create_shader , create_program genuinely working instead of only compiling.
to keep this runnable with no extra files needed, the shader source is written directly as strings here (create_shader takes source text directly) rather than loaded from .vert/.frag files on disk but it's calling the exact same create_shader/create_program wrappers
either way. if you DO want to test the file-loading + #include path specifically, save the vertex_src/fragment_src strings below into actual "triangle.vert" / "triangle.frag" files and swap the create_shader calls for create_shader_from_file instead     */

main :: proc() {
	glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(600, 600, "Shader Loader Demo", nil, nil)
	glfw.MakeContextCurrent(window)
	gl.load_up_to(4, 6, glfw.gl_set_proc_address)

	vertex_src := `#version 460 core
const vec2 pos[3] = vec2[3](vec2(-0.6, -0.6), vec2(0.6, -0.6), vec2(0.0, 0.6));
const vec3 col[3] = vec3[3](vec3(1,0,0), vec3(0,1,0), vec3(0,0,1));
layout(location = 0) out vec3 vColor;
void main() {
	gl_Position = vec4(pos[gl_VertexID], 0.0, 1.0);
	vColor = col[gl_VertexID];
}`

	fragment_src := `#version 460 core
layout(location = 0) in vec3 vColor;
layout(location = 0) out vec4 out_FragColor;
void main() {
	out_FragColor = vec4(vColor, 1.0);
}`

	// this is the part actually demonstrating the wrapper code above
	shader_vertex := create_shader(gl.VERTEX_SHADER, vertex_src)
	defer destroy_shader(&shader_vertex)

	shader_fragment := create_shader(gl.FRAGMENT_SHADER, fragment_src)
	defer destroy_shader(&shader_fragment)

	program := create_program(shader_vertex, shader_fragment)
	defer destroy_program(&program)

	vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao) // opengl still wants some vao bound, even though this shader hardcodes its own positions

	for !glfw.WindowShouldClose(window) {
		gl.Viewport(0, 0, 600, 600)
		gl.ClearColor(0.1, 0.1, 0.1, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		use_program(&program) // the wrapper doing its job every frame
		gl.DrawArrays(gl.TRIANGLES, 0, 3)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}

    
