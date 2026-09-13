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

// a small helper so we don't repeat the same slider code 3 times for r/g/b
bg_slider :: proc(ctx: ^mu.Context, channel: ^u8) {
	mu.push_id(ctx, uintptr(channel)) // gives this slider its own unique identity
	@(static) tmp: mu.Real
	tmp = mu.Real(channel^)
	mu.slider(ctx, &tmp, 0, 255, 0, "%.0f", {})
	channel^ = u8(tmp)
	mu.pop_id(ctx)
}

// now doing the main stuff , setting up the gui renderer , we don't do this in Imgui but in microgui we have to do it 

ui_init :: proc() {
	// this shader just takes 2D points and colors them in, nothing fancy.
	// UI is always flat/2D, so there's no camera or 3D math needed here.
	vertex_src := `#version 330 core
layout(location=0) in vec2 a_pos;
layout(location=1) in vec2 a_uv;
layout(location=2) in vec4 a_col;
out vec2 v_uv;
out vec4 v_col;
uniform mat4 u_proj;
void main() {
	gl_Position = u_proj * vec4(a_pos, 0.0, 1.0);
	v_uv = a_uv;
	v_col = a_col;
}`

	fragment_src := `#version 330 core
in vec2 v_uv;
in vec4 v_col;
out vec4 out_color;
uniform sampler2D u_tex;
void main() {
	// our font/icon image only stores brightness (not full color) 
	// we use that brightness as transparency, and let v_col choose the actual color
	float alpha = texture(u_tex, v_uv).r;
	out_color = vec4(v_col.rgb, v_col.a * alpha);
}`


vs := gl.CreateShader(gl.VERTEX_SHADER)
	src1 := cstring(raw_data(vertex_src))
	gl.ShaderSource(vs, 1, &src1, nil)
	gl.CompileShader(vs)

	fs := gl.CreateShader(gl.FRAGMENT_SHADER)
	src2 := cstring(raw_data(fragment_src))
	gl.ShaderSource(fs, 1, &src2, nil)
	gl.CompileShader(fs)

	ui.program = gl.CreateProgram()
	gl.AttachShader(ui.program, vs)
	gl.AttachShader(ui.program, fs)
	gl.LinkProgram(ui.program)
	gl.DeleteShader(vs)
	gl.DeleteShader(fs)

	gl.GenVertexArrays(1, &ui.vao)
	gl.GenBuffers(1, &ui.vbo)
	gl.GenBuffers(1, &ui.ebo)

	gl.BindVertexArray(ui.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, ui.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ui.ebo)

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(UI_Vertex), offset_of(UI_Vertex, pos))
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(UI_Vertex), offset_of(UI_Vertex, tex))
	gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, size_of(UI_Vertex), offset_of(UI_Vertex, col))

//now microui comes with built in small font + a few icons , already baked into one single image (atlas)
//we just need to upload it to the gpu once 

gl.GenTextures(1,&ui.atlas_tex)
gl.BindTexture(gl.TEXTURE_2D, ui.atlas_tex)
gl.TexImage2D(
   fl.TEXTURE_2D , 0 , gl.R8,
   mu.DEFAULT_ATLAS_WIDTH , mu,DEFAULT_ATLAS_HEIGHT, 0 ,
   gl.RED , gl.UNSIGNED_BYTE, &mu.default_atlas_alpha, )

gl.TexParameteri(gl.TEXTURE_2D , gl.TEXTURE_MIN_FILTER, gl.NEAREST)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

// telling the microui itself how wide / tall its built in font characters are , so it can lay out the text correctly 
mu.init(&ui.ctx)
ui.ctx.text_width = mu.default_atlas_text_width
ui.ctx.text_height = mu.default_atlas_text_height
}
