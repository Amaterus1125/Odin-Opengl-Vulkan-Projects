package main 

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

import "vendor:glfw"
import gl "vendor:OpenGL"
import mu "vendor:microui"

// in odin , for constants , do use Screaming style (all things are capital and stuff)

/* micro ui (using instead of imgui bc microui comes with odin support) is a tiny immediate mode GUI lib, meaning
instead of creating button/checkboxes objects once and keeping them around , we just draw a button for every frame 
and it figures out clicks, hovering and many more on the spot. hence no leftover GUI objects to manage 
in odin objects are kind of different bc odin is not OOP 

microui itself does not know how to draw anything on the screen , it only produces a list of instructions like draw a rectangle here 
or draw this text here , we take that list and turn it into actual opengl draw calls , this is what most of this file will do */ 

//now creating one point on our GUI sheet for -- where it is (pos) , which bit of the font/icon image to sample from (tex) , what color to tint it (col)

UI_Vertex :: struct {
   pos : [2]f32,
   tex: [2]f32,
   col: [4]u8,
}

//now creating everything out GUI system needs to remember between frames 
UI :: struct {
   ctx:  mu.Context,  //microui own internal state ( focus, layout , etc)
   program: u32,  // our 32 bit shader program for drawing gui shapes 
   vao , vbo , ebo : u32, // gpu buffers for the GUI shapes 
   atlas_text: u32,   //one image containing font and a few icons if needed 

/* now creating things for -- everyframe we collect ,all the little rectangles/text into these lists first ,
then send them to the gpu all at once (much faster then sending them one by one */
verts: [dynamic]UI_Vertex,
indices: [dynamic]u32,
}


ui : UI //one global instance to keep it simple 
win_width , win_height: i32 = 800, 600 // for updating each frame for the window size , like during resizes 

main :: proc() {
 glfw.Init()
 defer glfwTerminate()

 glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,3)
 glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR , 3)
 glfw.WindowHint(glfw.OPENGL_PROFILE , glfw.OPENGL_CORE_PROFILE)

 window := glfw.CreateWindow(win_width , win_height , "ODIN's EYE" , nil , nil)
 glfw.MakeContextCurrent(window)
 gl.load_up_to(3,3,glfw.gl.set_proc_address)

//now hooking up the mouse, keyboard and scrool events , setting callback procs near the bottom of the file 
glfw.SetCursorPosCallback(window, cursor_pos_callback)
glfw.SetMouseButtonCallback(window , mouse_button_callback)
glfw.SetScrollCallback(window, scroll_callback)
glfw.SetKeyCallback(window, key_callback)
glfw.SetCharCallback(window, char_callback)

ui_init()

//now a couple of variable our little demo GUI will let us control 
bg_color := mu.Color{90,95,100,255)
show_box:= true

for !glfw.WindowShouldClose(window) {
 w,h :=glfw.GetFramebufferSize(window)
 win_width , win_height = w, h 
 glfw.PollEvents()

// btw microui is much more control specific then Imgui , meaning u have to write a lot for microui , even yr own renderer , if u may use imgui , u can but idk how it's support with odin 

//now building the frame GUI -- the enxt blocks will describes what the gui will look like 
//right now microui compares it to the last frame to figure out like what changes , hovering or clicking 

mu.begin(&ui.ctx)
if mu.window(&ui.ctx . "THE EYE" . {50, 50 , 300 , 200}) {
 mu.layout_row(&ui.ctx , {-1} , 0)  //-1 means use the full width , & is the pointer initiator 
 mu.label(&ui.ctx , "THE ODIN EYE WAS POKED")

 if .SUBMIT in mu.button(&ui.ctx , "SHOW THE POKED EYE" , &show_box) {
   fmt.println("THE EYE WAS POKED") 
}

 if .CHANGE in mu.checkbox(&ui.ctx , "SHOW THE POKED EYE" , &show_box) {
   fmt.println("THE EYE IS NOW:" , show_box)
}

 mu.label(&ui.ctx , "INNER EYE:" )
mu.layout_row(&ui.ctx, {-1} , 0)
bg_slider(&ui.ctx , &bg_color.r)
bg_slider(&ui.ctx , 7bg_color.g)
bg_slider(&ui.ctx , 7bg_color.b)
}
mu.end(&ui.ctx)

// actual drawing for this frame 

gl.Viewport(0,0,win_width , win_height)
gl.ClearColor(f32(bg_color.r) / 255 , f32(bg_color.g) / 255 , f32(bg_color.b) / 255 , 1.0) // basically red , blue , green and opacity 
gl.Clear(gl.COLOR_BUFFER_BIT)

if show_box{
       //just a placeholder bit for our actual app or game rendering will go here 
}

ui_render()
glfw.SwapBuffers(window)
}
}
