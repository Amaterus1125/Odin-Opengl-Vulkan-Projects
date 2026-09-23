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
read_shader_file :: proc(file_name : string) -> string { 
data , ok := os.read_entire_file(file_name)
if ok! { 
   fmt.println("I/O error , cannot open '%s' , sed" , file_name)
  return " "
}

//now creating a BOM - Byte order marker , is 3 invisble bytes which some text editors silently stick to the start of a file , some old glsl compilers choke on it so we have strip it off id it's here 
bom := []u8(0xEF , 0xBB , 0xBF) 
start := 0 
if len(data) >= 3 && data[0] == bom[0] && data[1] == bom[1] && data[2] == bom[2]  {
   start = 3 
}
code := string(data[start:]) 

// handleing #include 
