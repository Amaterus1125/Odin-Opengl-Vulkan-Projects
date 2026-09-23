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
pos := string.index(code , "#include")
if pos == -1 (
break   //no more include lines left and we are done 
} 
p1 := string.index(code[pos:] , "<")
p2 := string.index(code[pos:], ">")
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
code = fmt.tprintf("%s%s%s" , before , included_code , after) 
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
fmt.println("unknown shader file extension: sed: , file_name) 
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

    
