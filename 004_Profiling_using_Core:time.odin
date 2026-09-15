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

	window := glfw.CreateWindow(800, 600, "THE NORNS", nil, nil)
	glfw.MakeContextCurrent(window)                         
	gl.load_up_to(4, 6, glfw.gl_set_proc_address) 


  //MEASUREING ONE - how long does making our gpu resources take ?
    t:= profile_start()  //remmeber the time right now 
    shader_vertex := gl.CreateShader(gl.VERTEX_SHADER)     // just creates an empty shader slot , vertex shader (both for creating the windows 
	shader_fragment := gl.CreateShader(gl.FRAGMENT_SHADER) // same, empty for now , fragment shader 
	per_frame_data_buffer: u32
	gl.CreateBuffers(1, &per_frame_data_buffer) // asks the gpu for 1 empty buffer

   profile_end("Creating Norms(Resources)" , t) // checking the time again and logging the difference as Create Resources

   //MEASURING 2 - how long does setting up GL take 
  t = profile_start()
  gl.ClearColor(1.0,1.0,1.0,1.0) // sets the background wipe color to white 
  gl.Enable(gl.DEPTH_TEST)  //turns on the 3d depth sorting (front covers the back)
  gl.Enable(gl.POLYGON_OFFSET_LINE)  // let us push wireframe lines slightly forward (avoids visual glitching)
  gl.PolygonOffset(-1.0,-1.0) //how far forward to push them 

 profile_end("SET THE NORMS" , t) 

//the next loop runs every frame until you close the window 
for !glfw.WindowShouldClose(window) {
     loop_start := profile_start() //times the entire frame , start to finish 
    //part 1 of frame work 
    part_start := profile_start() 
    time.sleep(2 * time.Millisecond) // stand in for 2 ms of actual work happening here 
    profile_end("NORM 1" , part_start) 

  // part 2 of a frame work 
  part_start = profile_start() 
  time.sleep(2 * time.Millisecond) 
  profile_end("NORM 2" , part_start)

 // timing glfw event checking specifically 
 part_start = profile_start()
 time.sleep( 2 * time.Millisecond) 
 glfw.PollEvents() //checking for things like window close and stuff
 profile_end("glfwPollEvents()" , part_start)
 profile_end("THE MAINLOOP" , loop_start) //logs the whole frame total time 
 // heads up - this never calls glfw.SwapBuffers() , so no picture on anything on the window , we are not drawing anything on the screen , insteas we are saving it on the text file
}

//once window is closed , write everything we measured to a text file so we can read it afterwords 
dump_profile_to_file("Profiler_Dump.txt")
gl.DeleteShader(shader_vertex)
gl.DeleteShader(shader_fragment)
gl.DeleteBuffers(1 , &per_frame_data_buffer)
}

/* now next parts turns everything we have logges into one big blobk of text and saves it to a file , we are keeping it 
as plain text , so any text editor can open it easily */

dump_profile_to_file :: proc(path: string) {
 sb: [dynamic]u8 // sb = string builder function and we build up our text one line at a time to do this 
defer delete(sb) //free the memory once the function is done

for entry in profile_log {
 //turns one entry into a line of text , like NORM 1 - 2.1 ms 
  line := fmt.aprintf("%s: %v\n" , entry.name , entry.duration)
  defer delete(line) // free this specific line from memory once we are done using it below 
  append(&sb , ..transmute([]u8)line) // add this lines bytes to the end of our growing text block  
}

//try to save this text block as a real file on the disk 
//error handling 

err := os.write_entire_file(path , sb[:])
if err != nil {
     fmt.eprintln("failed to write profile dump:", err) // eprintln = print as an error message
	} else {
		fmt.println("wrote profiling results to", path)
	}
}
