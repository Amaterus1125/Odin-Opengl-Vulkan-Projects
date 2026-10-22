// ADDITIONS ONLY FILE - paste under 002 chapter 3 in your combined file. No package line, nothing from previous repeated.
// This replaces the CPP Dear ImGui renderer with a MicroUI renderer, built as a REUSABLE layer.
// MicroUI ships with Odin (vendor:microui), so no extra dependency.

/* WHERE THE NEW CODE IS - 
 [MUI-1] MuiRenderer  - The reusable UI layer. One struct, init / update / fill_command_buffer / destroy.It knows NOTHING about your specific UI: you give it a "ui_proc" and it draws whatever that builds.
 [MUI-2] Input - mui_poll_glfw_input: feeds mouse position and buttons from GLFW into MicroUI.
 [MUI-3] Batching - Mui_update + mui_push_quad: turns MicroUI's commands (rect / text / icon / clip) into triangles and a list of draw calls (a new draw call whenever MicroUI changes the clip rectangle).
 [MUI-4] Shaders - The two small GLSL shaders for this layer are in a comment at the bottom (the book has none for MicroUI).
*/ 

/*  NOT REPEATED HERE (already in 011-014): Renderer / RendererBase / renderer_* helpers, VulkanImage, upload_memory,
 create_geometry_descriptor_set (014, with its optional texture binding), renderer_create_pipeline (014), create_buffer,
 create_descriptor_pool, vk_check, the clear / model / canvas / finish layers.

 /* 
IMPORTS (at the top of your file):   import mu "vendor:microui"
ASSUMPTIONS (same style as before):
a) create_graphics_pipeline has the optional params from 014 (topology, use_depth, use_blending, dynamic_scissor).
b) create_color_and_depth_framebuffers accepts depth_view = 0 (no depth buffer on this layer).
c) create_texture_image_from_data(device, physical_device, command_pool, queue, pixels: rawptr, width, height: i32,format: vk.Format, ^vk.Image, ^vk.DeviceMemory) -> bool    
d) The pipeline must NOT cull our triangles (cull mode NONE). If you see nothing on screen, check this first.
e) MicroUI names used: mu.default_atlas_alpha, mu.default_atlas, mu.DEFAULT_ATLAS_WIDTH / HEIGHT / WHITE / FONT If one is named differently in your Odin version, only [MUI-1] and [MUI-3] need touching.
*/ 

//  THE THINGS TO REMEMBER 
/*
 1. HOW TO REUSE IT: write a proc  my_ui :: proc(ctx: ^mu.Context, user_data: rawptr)  that calls mu.window / mu.button / ... .
   Then  mui_init(&layer, &vk_dev, my_ui, &my_data, vert, frag).   That's all. Any number of layers can exist with different procs.
   (One layer = one MicroUI context. Several windows that should share focus/hover belong in the SAME ui_proc, as several
   mu.window() calls. Use a second layer only for a truly separate UI.)
 2. MicroUI is immediate mode: every frame it re-runs your ui_proc and produces a list of commands.
  Command_Rect  -> one quad using the atlas's white pixel
  Command_Text  -> one quad PER CHARACTER, sampled from the font atlas
  Command_Icon  -> one quad from the atlas
  Command_Clip  -> "from now on, only draw inside this rectangle"  => we start a new draw call with a new scissor
 3. One 128x128 atlas (built into MicroUI) holds the font, the icons and a white pixel. Its alpha-only bitmap is expanded to
   RGBA (white + alpha) so the fragment shader can just do  colour * texture.
 4. Same GPU recipe as the canvas: vertex pulling, ONE storage buffer per swapchain image, 6 vertices per quad (no index buffer).
 5. It's a MIDDLE layer without depth.  Order:  clear -> model -> canvas -> ui -> finish
 6. Per frame:  mui_poll_glfw_input -> mui_update(image_index) -> (record) layer.fill_command_buffer.
 7. Want to know if the mouse is over the UI (so the camera shouldn't move)?   layer.ctx.hover_root != nil
*/ 

// MuiRenderer - the reusable layer 

ONE VERTEX = 2d PIXEL POSITION + ATLAS UV + color = 20 bytes (the shader reads it as 4 floats + 1 uint) 
MuiVertex :: struct { 
pos: [2]f32 , 
uv: [2]f32 , 
color : [4]u8 , 
} 

//one draw call - a run of vertices drawn with one scissor rectangle 
MuiDrawCall :: struct { 
first_vertex : u32 , 
vertex_count : u32 , 
clip : mu.Rect , 
} 

// the user UI , build windows and widgets here , called once per frame between mu.begn and mu.end 
MuiUiProc :: proc(ctx : ^mu.Context , user_data : rawptr) 
MUI_MAX_VERTICES :: 65536 // about 10,900 quads per frame (rects + characters) 
MUI_VERTEX_DATA_SIZE :: MUI_MAX_VERTICES * size_of(MuiVertex) 

MuiRenderer :: struct { 
using renderer : Renderer , // keep first always 
ctx : ^mu.Context , // on the healp , a microui context is large (in kb) 
ui_proc: MuiUiProc , 
user_data : rawptr ,// handed to ui_proc untouched (our ui state) 

//rebuilt every frame by mui_update 
vertices : [dynamic]MuiVertex , 
draw_calls : [dynamic]MUiDrawCall , 
// GPU side 
storage_buffers : []vk.Buffer // the vertices , one buffer per swapchain image 
storage_buffers_memory: []vk.DeviceMemory,
atlas:  VulkanImage,
atlas_sampler: vk.Sampler,
mouse_down: [3]bool, // previous left/right/middle button state, for press/release edges
}

// MicroUI asks us how wide / tall text is. Our font is the built-in atlas font: every glyph's width comes from the atlas.
mui_text_width :: proc(font: mu.Font, str: string) -> (res: i32) {
	for ch in str {
		if ch & 0xc0 == 0x80 { continue } // skip UTF-8 continuation bytes
		r := min(int(ch), 127)
		res += i32(mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r].w)
	}
	return
}
mui_text_height :: proc(font: mu.Font) -> i32 { return 18 }

mui_init :: proc(
self: ^MuiRenderer, vk_dev: ^VulkanRenderDevice,
ui_proc: MuiUiProc, user_data: rawptr, vert_file, frag_file: string,) -> bool {
renderer_base_init(&self.base, vk_dev, VulkanImage{}) // no depth: the UI is drawn on top of everything
self.fill_command_buffer = mui_fill_command_buffer
self.destroy = mui_destroy
self.ui_proc  = ui_proc
self.user_data  = user_data

// the MicroUI context
self.ctx = new(mu.Context)
mu.init(self.ctx)
self.ctx.text_width  = mui_text_width
self.ctx.text_height = mui_text_height

ok : bool 
image_count := len(vk_dev.swapchain_images) 
// atlas is basically the 
// the atlas: expand the 1-byte-per-pixel alpha bitmap to RGBA (white, alpha = bitmap) and upload it as a texture
rgba := make([]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT * 4)
defer delete(rgba)
for i in 0 ..< mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT {
rgba[i * 4 + 0] = 255
rgba[i * 4 + 1] = 255
rgba[i * 4 + 2] = 255
rgba[i * 4 + 3] = mu.default_atlas_alpha[i]
}

if !create_texture_image_from_data(
vk_dev.device, vk_dev.physical_device, vk_dev.command_pool, vk_dev.graphics_queue,
raw_data(rgba), mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT, .R8G8B8A8_UNORM,
&self.atlas.image, &self.atlas.memory,) { return false }
self.atlas.view, ok = create_image_view(vk_dev.device, self.atlas.image, .R8G8B8A8_UNORM, {.COLOR})
if !ok { return false }
self.atlas_sampler, ok = create_texture_sampler(vk_dev.device) // if the text looks blurry, make this sampler NEAREST
if !ok { return false }

// one vertex buffer per swapchain image, CPU-writable
self.storage_buffers        = make([]vk.Buffer, image_count)
self.storage_buffers_memory = make([]vk.DeviceMemory, image_count)
for i in 0 ..< image_count {
self.storage_buffers[i], self.storage_buffers_memory[i], ok = create_buffer(
vk_dev.device, vk_dev.physical_device, MUI_VERTEX_DATA_SIZE, {.STORAGE_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
)
if !ok { return false }
}

// uniform buffer = just the 2D projection matrix
	if !renderer_create_uniform_buffers(&self.base, vk_dev, size_of(matrix[4, 4]f32)) { return false }

// pool counts per image: 1 uniform, 1 storage, 1 sampler
self.descriptor_pool, ok = create_descriptor_pool(vk_dev.device, u32(image_count), 1, 1, 1)
if !ok { return false }
self.descriptor_set_layout, self.descriptor_sets, ok = create_geometry_descriptor_set(
vk_dev.device, self.descriptor_pool, self.uniform_buffers, size_of(matrix[4, 4]f32),self.storage_buffers, MUI_VERTEX_DATA_SIZE, self.atlas_sampler, self.atlas.view,)
if !ok { return false }

// middle layer, no depth
self.render_pass, ok = create_color_and_depth_render_pass(vk_dev.device, false, RenderPassCreateInfo{})
if !ok { return false }
// triangles, no depth test, blending ON (text edges), dynamic scissor ON (a new clip rect per draw call)
if !renderer_create_pipeline(&self.base, vk_dev, vert_file, frag_file, .TRIANGLE_LIST, false, true, true) { return false }

self.swapchain_framebuffers, ok = create_color_and_depth_framebuffers(vk_dev, self.render_pass, 0, self.framebuffer_width, self.framebuffer_height)
return ok
}

// records this layer. No draw calls = no render pass (it is a middle layer, so skipping it is fine).
mui_fill_command_buffer :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, current_image: u32) {
self := cast(^MuiRenderer)r
if len(self.draw_calls) == 0 { return }
renderer_begin_render_pass(&self.base, command_buffer, current_image)
fb_w := i32(self.framebuffer_width)
fb_h := i32(self.framebuffer_height)
for dc in self.draw_calls {
// MicroUI's "unclipped" rectangle is huge, so clamp the clip rect to the framebuffer
x0 := clamp(dc.clip.x, 0, fb_w)
y0 := clamp(dc.clip.y, 0, fb_h)
x1 := clamp(dc.clip.x + dc.clip.w, 0, fb_w)
y1 := clamp(dc.clip.y + dc.clip.h, 0, fb_h)
if x1 <= x0 || y1 <= y0 { continue } // nothing visible inside this clip rect
scissor := vk.Rect2D{offset = {x = x0, y = y0}, extent = {width = u32(x1 - x0), height = u32(y1 - y0)}}
vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
vk.CmdDraw(command_buffer, dc.vertex_count, 1, dc.first_vertex, 0)
}
vk.CmdEndRenderPass(command_buffer)
}


mui_destroy :: proc(r: ^Renderer) {
self := cast(^MuiRenderer)r
vk.DestroySampler(self.device, self.atlas_sampler, nil)
vk.DestroyImageView(self.device, self.atlas.view, nil)
vk.DestroyImage(self.device, self.atlas.image, nil)
vk.FreeMemory(self.device, self.atlas.memory, nil)

for i in 0 ..< len(self.storage_buffers) { destroy_buffer(self.device, self.storage_buffers[i], self.storage_buffers_memory[i]) }
delete(self.storage_buffers)
delete(self.storage_buffers_memory)
delete(self.vertices)
delete(self.draw_calls)
free(self.ctx)
renderer_base_destroy(&self.base)
}

// INPUT - GLFW -> MICROUI 
mui_poll_glfw_input :: proc(self: ^MuiRenderer, window: glfw.WindowHandle) {
xf, yf := glfw.GetCursorPos(window)
x, y := i32(xf), i32(yf)
mu.input_mouse_move(self.ctx, x, y)
buttons := [3]mu.Mouse{.LEFT, .RIGHT, .MIDDLE}
glfw_buttons := [3]i32{glfw.MOUSE_BUTTON_LEFT, glfw.MOUSE_BUTTON_RIGHT, glfw.MOUSE_BUTTON_MIDDLE}
for i in 0 ..< 3 {
down := glfw.GetMouseButton(window, glfw_buttons[i]) == glfw.PRESS
if down && !self.mouse_down[i] {
mu.input_mouse_down(self.ctx, x, y, buttons[i])} else if !down && self.mouse_down[i] {
mu.input_mouse_up(self.ctx, x, y, buttons[i])
}
self.mouse_down[i] = down
}
}

// Batching - MicroUI commands -> triangles + draw calls

// two triangles (6 vertices) for one rectangle: `dst` is where it goes on screen (pixels), `src` is the atlas region to sample
mui_push_quad :: proc(self: ^MuiRenderer, dst, src: mu.Rect, color: mu.Color) {
	if len(self.vertices) + 6 > MUI_MAX_VERTICES { return } // GPU buffer is full: drop the rest of this frame's UI

// atlas pixel rect -> 0..1 texture coordinates
u0 := f32(src.x) / f32(mu.DEFAULT_ATLAS_WIDTH)
v0 := f32(src.y) / f32(mu.DEFAULT_ATLAS_HEIGHT)
u1 := f32(src.x + src.w) / f32(mu.DEFAULT_ATLAS_WIDTH)
v1 := f32(src.y + src.h) / f32(mu.DEFAULT_ATLAS_HEIGHT)
x0 := f32(dst.x)
y0 := f32(dst.y)
x1 := f32(dst.x + dst.w)
y1 := f32(dst.y + dst.h)
c  := [4]u8{color.r, color.g, color.b, color.a}
append(&self.vertices, MuiVertex{{x0, y0}, {u0, v0}, c}) // triangle 1
append(&self.vertices, MuiVertex{{x1, y0}, {u1, v0}, c})
append(&self.vertices, MuiVertex{{x0, y1}, {u0, v1}, c})
append(&self.vertices, MuiVertex{{x1, y0}, {u1, v0}, c}) // triangle 2
append(&self.vertices, MuiVertex{{x1, y1}, {u1, v1}, c})
append(&self.vertices, MuiVertex{{x0, y1}, {u0, v1}, c})
}

// close the current run of vertices as one draw call (does nothing if the run is empty)
mui_flush_batch :: proc(self: ^MuiRenderer, batch_start: ^int, clip: mu.Rect) {
count := len(self.vertices) - batch_start^
if count > 0 {
append(&self.draw_calls, MuiDrawCall{first_vertex = u32(batch_start^), vertex_count = u32(count), clip = clip})
batch_start^ = len(self.vertices)
}
}

/* THE per-frame call. In order:
1. run the user's UI (mu.begin -> ui_proc -> mu.end)
2. walk MicroUI's command list and turn it into vertices + draw calls
3. upload the vertices and the projection matrix to this swapchain image's buffers */
mui_update :: proc(self: ^MuiRenderer, vk_dev: ^VulkanRenderDevice, current_image: u32) {
// 1. build the UI
mu.begin(self.ctx)
self.ui_proc(self.ctx, self.user_data)
mu.end(self.ctx)

// 2. commands -> quads
clear(&self.vertices)
clear(&self.draw_calls)

clip := mu.Rect{0, 0, i32(self.framebuffer_width), i32(self.framebuffer_height)} // start with the whole screen
batch_start := 0
