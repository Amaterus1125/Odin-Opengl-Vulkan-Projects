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



    
