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


