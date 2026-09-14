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
   atlas_tex: u32,   //one image containing font and a few icons if needed 

/* now creating things for -- everyframe we collect ,all the little rectangles/text into these lists first ,
then send them to the gpu all at once (much faster then sending them one by one */
verts: [dynamic]UI_Vertex,
indices: [dynamic]u32,
}


ui : UI //one global instance to keep it simple 
win_width , win_height: i32 = 800, 600 // for updating each frame for the window size , like during resizes 

main :: proc() {
 glfw.Init()
 defer glfw.Terminate()

 glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,3)
 glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR , 3)
 glfw.WindowHint(glfw.OPENGL_PROFILE , glfw.OPENGL_CORE_PROFILE)

 window := glfw.CreateWindow(win_width , win_height , "ODIN's EYE" , nil , nil)
 glfw.MakeContextCurrent(window)
 gl.load_up_to(3,3,glfw.gl_set_proc_address)

//now hooking up the mouse, keyboard and scrool events , setting callback procs near the bottom of the file 
glfw.SetCursorPosCallback(window, cursor_pos_callback)
glfw.SetMouseButtonCallback(window , mouse_button_callback)
glfw.SetScrollCallback(window, scroll_callback)
glfw.SetKeyCallback(window, key_callback)
glfw.SetCharCallback(window, char_callback)

ui_init()

//now a couple of variable our little demo GUI will let us control 
bg_color := mu.Color{90,95,100,255}
show_box:= true

for !glfw.WindowShouldClose(window) {
 w,h :=glfw.GetFramebufferSize(window)
 win_width , win_height = w, h 
 glfw.PollEvents()

// btw microui is much more control specific then Imgui , meaning u have to write a lot for microui , even yr own renderer , if u may use imgui , u can but idk how it's support with odin 

//now building the frame GUI -- the enxt blocks will describes what the gui will look like 
//right now microui compares it to the last frame to figure out like what changes , hovering or clicking 

mu.begin(&ui.ctx)
if mu.window(&ui.ctx , "THE EYE" , {50, 50 , 300 , 200}) {
 mu.layout_row(&ui.ctx , {-1} , 0)  //-1 means use the full width , & is the pointer initiator 
 mu.label(&ui.ctx , "THE ODIN EYE WAS POKED")

 if .SUBMIT in mu.button(&ui.ctx , "POKE THE EYE") {
   fmt.println("THE EYE WAS POKED") 
}

 if .CHANGE in mu.checkbox(&ui.ctx , "SHOW THE POKED EYE" , &show_box) {
   fmt.println("THE EYE IS NOW:" , show_box)
}

 mu.label(&ui.ctx , "INNER EYE:" )
mu.layout_row(&ui.ctx, {-1} , 0)
bg_slider(&ui.ctx , &bg_color.r)
bg_slider(&ui.ctx , bg_color.g)
bg_slider(&ui.ctx , bg_color.b)
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

//takes in three attributes per vertex , position , uv texture for microui , color at the attribute locations 0 , 1 and 2 , these must match the VertexAttributePointer calls later
//then passed to fragment shader later on and location must be matched 
//u_proj is a projection matrix uniform , that converts pixel coordinates into opengl normalizes device coordinates(-1 to 1)

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


/* the font/icon atlas is a single channled image (red only i.e. R8) storing just brightness and coverage , 
this shader reads that single red channel as an alpha mask and multiplies into the vertex color alpha , so white text tinted red jsut becomes red 
glyph shapes with the atlas defining there coverage/ anti-aliasing */
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

// compiling and linking shaders object as cstrings used in odin , same we will do for the fragment shader too we just created 
vs := gl.CreateShader(gl.VERTEX_SHADER)
	src1 := cstring(raw_data(vertex_src))
	gl.ShaderSource(vs, 1, &src1, nil)
	gl.CompileShader(vs)

	fs := gl.CreateShader(gl.FRAGMENT_SHADER)
	src2 := cstring(raw_data(fragment_src))
	gl.ShaderSource(fs, 1, &src2, nil)
	gl.CompileShader(fs)

//creates a program object , attaches both shader stages , links them into one usable pipeline , the indivitual shader objects can then be deleted and program keeps the copy of the compiled code 
	ui.program = gl.CreateProgram()
	gl.AttachShader(ui.program, vs)
	gl.AttachShader(ui.program, fs)
	gl.LinkProgram(ui.program)
	gl.DeleteShader(vs)
	gl.DeleteShader(fs)

// allocates and bindes the vao (vertex array object) to vbo( will hold vertex data for the framebuffer) and ebo(will hold the triangle indices) 
//binding happens once here , the actual data is updated every frame in ui_flush
	gl.GenVertexArrays(1, &ui.vao)
	gl.GenBuffers(1, &ui.vbo)
	gl.GenBuffers(1, &ui.ebo)

	gl.BindVertexArray(ui.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, ui.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ui.ebo)

/* 


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
   gl.TEXTURE_2D , 0 , gl.R8,
   mu.DEFAULT_ATLAS_WIDTH , mu.DEFAULT_ATLAS_HEIGHT, 0 ,
   gl.RED , gl.UNSIGNED_BYTE, &mu.default_atlas_alpha, )

gl.TexParameteri(gl.TEXTURE_2D , gl.TEXTURE_MIN_FILTER, gl.NEAREST)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

// telling the microui itself how wide / tall its built in font characters are , so it can lay out the text correctly 
mu.init(&ui.ctx)
ui.ctx.text_width = mu.default_atlas_text_width
ui.ctx.text_height = mu.default_atlas_text_height
}

// now adding one rectangle (as 2 triangles) to this frame's batch of shapes to draw 
ui_push_quad :: proc(dst , src: mu.Rect , color:mu.Color) {
   idx := u32(len(ui.verts))
   atlas_w , atlas_h := f32(mu.DEFAULT_ATLAS_WIDTH) , f32(mu.DEFAULT_ATLAS_HEIGHT)
	u0, v0 := f32(src.x) / atlas_w, f32(src.y) / atlas_h
	u1, v1 := f32(src.x + src.w) / atlas_w, f32(src.y + src.h) / atlas_h

	x0, y0 := f32(dst.x), f32(dst.y)
	x1, y1 := f32(dst.x + dst.w), f32(dst.y + dst.h)

	col := [4]u8{color.r, color.g, color.b, color.a}
    append(&ui.verts,
		UI_Vertex{{x0, y0}, {u0, v0}, col},
		UI_Vertex{{x1, y0}, {u1, v0}, col},
		UI_Vertex{{x1, y1}, {u1, v1}, col},
		UI_Vertex{{x0, y1}, {u0, v1}, col},
	)
	append(&ui.indices, idx, idx + 1, idx + 2, idx, idx + 2, idx + 3)
}


ui_flush :: proc() {
	if len(ui.indices) == 0 {
		return
	}
	gl.BindVertexArray(ui.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, ui.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(ui.verts) * size_of(UI_Vertex), raw_data(ui.verts), gl.STREAM_DRAW)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ui.ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(ui.indices) * size_of(u32), raw_data(ui.indices), gl.STREAM_DRAW)
	gl.DrawElements(gl.TRIANGLES, i32(len(ui.indices)), gl.UNSIGNED_INT, nil)

	clear(&ui.verts)
	clear(&ui.indices)
}
// walks through everything microui wants drawn this frame, and turns
// each instruction into actual triangles on screen
ui_render :: proc() {
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA) // lets semi-transparent ui edges blend nicely
	gl.Disable(gl.DEPTH_TEST)                          // ui is always flat, depth doesn't apply
	gl.Enable(gl.SCISSOR_TEST)                         // lets us clip a window's contents to its own box

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, ui.atlas_tex)
	gl.UseProgram(ui.program)

// a flat 2D "camera" -- just maps pixel coordinates directly to the screen
	l, r := f32(0), f32(win_width)
	b, t := f32(win_height), f32(0)
	proj := [16]f32 {
		2 / (r - l), 0, 0, 0,
		0, 2 / (t - b), 0, 0,
		0, 0, -1, 0,
		-(r + l) / (r - l), -(t + b) / (t - b), 0, 1,
	}
	loc := gl.GetUniformLocation(ui.program, "u_proj")
	gl.UniformMatrix4fv(loc, 1, false, &proj[0])
	tex_loc := gl.GetUniformLocation(ui.program, "u_tex")
	gl.Uniform1i(tex_loc, 0)

	command: ^mu.Command
	for variant in mu.next_command_iterator(&ui.ctx, &command) {
		#partial switch cmd in variant {
		case ^mu.Command_Text:
			dst := mu.Rect{cmd.pos.x, cmd.pos.y, 0, 0}
			for ch in cmd.str {
				r := min(int(ch), 127)
				src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
				dst.w, dst.h = src.w, src.h
				ui_push_quad(dst, src, cmd.color)
				dst.x += dst.w
			}
		case ^mu.Command_Rect:
			white := mu.default_atlas[mu.DEFAULT_ATLAS_WHITE] // a flat white pixel, tinted by color
			ui_push_quad(cmd.rect, white, cmd.color)
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			ui_push_quad(mu.Rect{x, y, src.w, src.h}, src, cmd.color)
		case ^mu.Command_Clip:
			ui_flush() // must draw what we have BEFORE changing the clip region
			gl.Scissor(cmd.rect.x, win_height - (cmd.rect.y + cmd.rect.h), cmd.rect.w, cmd.rect.h)
		}
	}
	ui_flush()
	gl.Scissor(0, 0, win_width, win_height) // reset clipping back to the whole screen
}

// ============================================================
// INPUT CALLBACKS -- GLFW calls these automatically, we just forward
// the info into microui's input system
// ============================================================

cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = runtime.default_context()
	mu.input_mouse_move(&ui.ctx, i32(x), i32(y))
}

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = runtime.default_context()
	x, y := glfw.GetCursorPos(window)
	mu_button: mu.Mouse
	switch button {
	case glfw.MOUSE_BUTTON_LEFT: mu_button = .LEFT
	case glfw.MOUSE_BUTTON_RIGHT: mu_button = .RIGHT
	case glfw.MOUSE_BUTTON_MIDDLE: mu_button = .MIDDLE
	case: return
	}
	if action == glfw.PRESS {
		mu.input_mouse_down(&ui.ctx, i32(x), i32(y), mu_button)
	} else if action == glfw.RELEASE {
		mu.input_mouse_up(&ui.ctx, i32(x), i32(y), mu_button)
	}
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoff, yoff: f64) {
	context = runtime.default_context()
	mu.input_scroll(&ui.ctx, i32(xoff * 30), i32(yoff * -30))
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	mu_key: mu.Key
	switch key {
	case glfw.KEY_LEFT_SHIFT, glfw.KEY_RIGHT_SHIFT: mu_key = .SHIFT
	case glfw.KEY_LEFT_CONTROL, glfw.KEY_RIGHT_CONTROL: mu_key = .CTRL
	case glfw.KEY_LEFT_ALT, glfw.KEY_RIGHT_ALT: mu_key = .ALT
	case glfw.KEY_ENTER: mu_key = .RETURN
	case glfw.KEY_BACKSPACE: mu_key = .BACKSPACE
	case: return
	}
	if action == glfw.PRESS {
		mu.input_key_down(&ui.ctx, mu_key)
	} else if action == glfw.RELEASE {
		mu.input_key_up(&ui.ctx, mu_key)
	}
}

// lets you actually type into text boxes (turns the typed character into text microui understands)
char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	buf, n := utf8.encode_rune(codepoint)
	mu.input_text(&ui.ctx, string(buf[:n]))
}

