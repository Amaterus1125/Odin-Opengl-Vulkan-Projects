//BASIC IMPORTS FOR ALL PROFILING NEEDS , NOT USING EASY PROFILER AS ODIN DOES NOT HAVE ITS SUPPORT OKK

package main

import "core:fmt"
import "core:os"
import "core:time"

import "vendor:glfw"
import gl "vendor:OpenGL"

/* WHAT IS PROFILING - timing pieces of your code to see which parts are slow , we mark "start point" right before
some code and "end point" right after it , and look at the gap between those two moments to rell you how long that code will take

Odin does not have easy profiler , so instead we are building the same basic idea ourselves using the core:time package */

//this holds one measurment , what we were timing ( the name) and how long did it took (the duration)

Pro_Entry :: struct {
 name : string,
 duration: time.Duration, // odin built in type for an amount of time 
}

//as the program runs , everytime we finish timing something ,we add one of these to the list , at the very end we write the whole list out to a file so we can take a look later
profile_log: [dynamic]Pro_Entry

//call this the moment before the code you want to measure starts 
profile_start :: proc() -> time.Time { 
    return time.now()   //just reads the current clock time , nothing else   
}

// call this right after that code finishes , name = what to label this measurment as and start_time = whenever profile_start() gave you earlier for this block 
profile_end :: proc(name : string , start_time: time.Time) {
   elapsed := time.since(start_time)  //how much time has passed since start_time 
   append(&profile_log, Pro_Entry{name , elapsed}) // save it for later 
}

// the main executable procedure

main :: proc() {
   glfw.Init()
  defer glfw.Terminate() // runs automatically when main() ends , closes glfw cleanly 
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(800, 600, "Profile Easy", nil, nil)
	glfw.MakeContextCurrent(window)                         
	gl.load_up_to(4, 6, glfw.gl_set_proc_address) 

  
