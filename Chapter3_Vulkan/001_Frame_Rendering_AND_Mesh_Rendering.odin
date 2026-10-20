/* WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
1. Paste everything below into your existing chapter file, UNDER what 012 already added.
2. There is no `package` line and no imports here, and NOTHING from 011/012 is repeated (otherwise Odin would complain about names declared twice, like MeshBuffer). This file REUSES these things from 011/012 -
   MeshBuffer, create_textured_vertex_buffer, create_descriptor_pool, create_descriptor_set, shader_stage_info, create_buffer, destroy_buffer, UniformBuffer
   and from the older chapter 3 helpers (same assumed signatures as in the 012 header comment) - create_texture_image, create_image_view, create_texture_sampler, create_depth_resources, create_shader_module,
   create_color_and_depth_render_pass, create_pipeline_layout, create_graphics_pipeline, create_color_and_depth_framebuffers
3. EXTRA ASSUMPTION: VulkanRenderDevice also has u32 fields `framebuffer_width` and `framebuffer_height` (the book's vkDev.framebufferWidth/Height).  */

/* THIS FILE = CHAPTER 4, RECIPES 1 AND 2:
   "Organizing Vulkan frame rendering code" -> RendererBase, VulkanClear, VulkanFinish
   "Organizing mesh rendering in Vulkan" -> ModelRenderer  */

// WHAT WE ARE DOING - 
/* think of one frame as layers, like an image in a graphics editor - 
layer 1 - clear the screen to a background color using VulkanClear 
layer 2 - the 3d model using ModelRenderer
last part - move the image into the ready to present layout using VulkanFinish 

Every layer is an object that owns its own pipeline, render pass, framebuffers, descriptor sets and buffers, and can
record its commands into a command buffer. Then drawing a frame is just - "for each layer, ask it to record commands".

Odin has no classes, so we use two Odin tools instead - 
1. STRUCT EMBEDDING with `using`: ModelRenderer contains a Renderer which contains a RendererBase, and `using` makes all their fields available directly (model.render_pass works, no model.base.render_pass needed).
2. PROCEDURE POINTERS: the "virtual function" fill_command_buffer is just a field holding a proc. Each layer sets its own proc when it is created.
That is why every layer struct has `using renderer - Renderer` as its FIRST field: then a pointer to the layer and a pointer
to its Renderer are the same address, and we can safely cast between them inside the layer procs. */

// PART 1 - RendererBase - the state every layer shares

/* one vulkan image together with its memory and view (the VulkanImage) and a zeroed VulkanImage() means "no image" (image = 0) , which VulkanClear/VulkanFinish use to use to mean "no depth buffer" */

VulkanImage :: struct { 
image : vk.Image ,
memory : vk.DeviceMemory, 
view : vk.ImageView , 
} 

//  RendererBase class (its fields - the functions are free procs below)
RendererBase :: struct 
device : vk.Device , 
//each layer uses the framebuffer size to start its render pass 
framebuffer_width : u32 , 
framebuffer_height : u32 , 

// all textures and buffers reach the shaders through descriptor , one set per swapchain image ,to define them we also need the layout and the pool they come from 
descriptor_set_layout : vk.DescriptorSetLayout , 
descriptor_pool: vk.DescriptorPool , 
descriptor_sets : []vk.DescriptorSet, 

//each command buffer works on its own framebuffer (one per swapchain image) 
swapchain_framebuffers : []vk.DescriptorSet , 

//the depth buffer , it is only refrenced once , so it can be shared between layers , whoever created it destroys it too 
depth_texture : VulkanImage , 
render_pass : vk.RenderPass , 
pipeline_layout : vk.PipelineLayout , 
graphics_pipeline : vk.Pipeline, 

//each swapchain image has its own uniform buffer (so we never owerwrite one the gpu is still reading) 
uniform_buffers: []vk.Buffer, 
uniform_buffers_memory: []vk.DeviceMemory , 
} 

/* the "interface" every layer implements (pure virtual fillCommandBuffer + the destructor), a layer fills in these two procedure pointers when it is initialized */ 
Renderer :: struct { 
using base: RenderBase , 

//injects a stream of vulkan commands into the given command buffer , current_image picks the uniform buffer , descriptor set and framebuffer that belong to one of the swapchain images 
fill_command_buffer : proc(self : ^Renderer , command_buffer : vk.CommandBuffer , current_image : u32) , 
//free everythings this laeyr allocated , odin has no destructors sp we call it by hand
destroy : proc(self: ^Renderer) , 
} 

// the constructor part of the base class , remember the device , the framebuffer size and the (possibly empty) depth buffer 
renderer_base_init :: proc(self : ^RendererBase , vk_dev : ^VulkanRendererDevice , depth_texture : VulkanImage ) { 
self.device = vk_dev.device 
self.framebuffer_width = vk_dev.framebuffer_width
self.framebuffer_height = vk_dev.framebuffer_height 
self.depth_texture = depth_texture 
} 

// allocates the uniform buffer , a simple loop over all swapchain images , one buffer each 

renderer_create_uniform_buffers :: proc(self: ^RendererBase, vk_dev: ^VulkanRenderDevice, uniform_data_size: vk.DeviceSize) -> bool {
image_count := len(vk_dev.swapchain_image) 
self.uniform_buffer = make([]vk.Buffer , image_count) 
self.uniform_buffer_memory - make([]vk.DeviceMemory , image_count) 

for i in ..< image_count { 
ok : bool 
// HOST_VISIBLE + HOST_COHERENT - the CPU can write the data every frame with no extra flushing
self.uniform_buffer[i], self.uniform_buffer_memory[i], ok = create_buffer( 
vk_dev.device , vk_dev.physical_device , uniform_data_size , {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
} 
if !ok {
fmt.println("Cannot create uniform buffer, now what should we do")
return false
}}
return true
}

/* Marks the start of a render pass and binds the graphics pipeline + the descriptor set of the current swapchain image.
   Derived layers call this first, then record their own draw commands, then call vk.CmdEndRenderPass. */

renderer_begin_render_pass :: proc(self : ^RendererBase , command_buffer: vk.CommandBuffer , current_image : u32) { 
screen_rect := vk.Rect2D{
offset = {0, 0},
extent = {width = self.framebuffer_width, height = self.framebuffer_height},
}
render_pass_info := vk.RenderPassBeginInfo{
sType = .RENDER_PASS_BEGIN_INFO,
renderPass  = self.render_pass,
framebuffer = self.swapchain_framebuffers[current_image],
renderArea  = screen_rect,
}
vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
vk.CmdBindPipeline(command_buffer, .GRAPHICS, self.graphics_pipeline)
vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, self.pipeline_layout, 0, 1, &self.descriptor_sets[current_image], 0, nil)
}

/* The destructor: cleans up every object in the base. In a bigger app you would wrap each resource so this happens
automatically; here we do it by hand. Note this assumes the objects were actually allocated by the layer's init. Layers that never made some of them
(e.g. VulkanClear has no descriptor pool) are still fine - Vulkan ignores destroy calls on null handles. */

renderer_base_destroy :: proc(self: ^RendererBase) {
for i in 0 ..< len(self.uniform_buffers) {
destroy_buffer(self.device, self.uniform_buffers[i], self.uniform_buffers_memory[i])
}
delete(self.uniform_buffers)
delete(self.uniform_buffers_memory)
vk.DestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, nil)
vk.DestroyDescriptorPool(self.device, self.descriptor_pool, nil) // also frees the sets that came from it
delete(self.descriptor_sets)
for fb in self.swapchain_framebuffers { vk.DestroyFramebuffer(self.device, fb, nil) }
delete(self.swapchain_framebuffers)
vk.DestroyRenderPass(self.device, self.render_pass, nil)
vk.DestroyPipelineLayout(self.device, self.pipeline_layout, nil)
vk.DestroyPipeline(self.device, self.graphics_pipeline, nil)
}

// the `destroy` entry for layers that need nothing beyond the base cleanup (VulkanClear and VulkanFinish)
renderer_destroy_base_only :: proc(self: ^Renderer) {
renderer_base_destroy(&self.base)
}

// PART 2 - VulkanClear - the first layer, clears the colour (and depth) buffer

VulkanClear :: struct { 
using renderer : Renderer , //always keep first 
should_clear_depth : bool , // false if there is no depth image 
} 

vulkan_clear_init :: proc(self : ^VulkanClear , vk_dev : ^VulkanRenderDevice , depth_texture : VulkanImage) -> bool { 
renderer_base_init (&self.base , vk_dev , depth_texture) 
self.should_clear_depth = depth_texture.image != 0 
self.fill_command_buffer = vulkan_clear_fill_command_buffer 
self.destroy = renderer_destroy_base_only 

ok: bool 
self.render_pass , ok = create_color_and_depth_render_pass( 
vk_dev.device , self.should_clear_depth, 
RenderPassCreateInfo(clear_color = true , clear_depth = true , flags = {.First} } ,
} 
if !ok { 
fmt.println("VulkanClear has faield to create render pass") 
return false 
} 
self.swapchain_framebuffers, ok = create_color_and_depth_framebuffers(
vk_dev, self.render_pass, depth_texture.view, self.framebuffer_width, self.framebuffer_height,
)
return ok
}

vulkan-clear_fill_command_buffer :: proc(r: ^Renderer , command_buffer: vk.CommandBuffer,current_image: u32) { 
self := cast(^VulkanClear)r
clear_values := [2]vk.ClearValue{ 
{color = {float32 = {1.0, 1.0 ,1.0 ,1.0} }} //for white background 
{depthStencil = {depth = 1.0 , stencil =0 }}. //1.0 means farthest 
} 
render_pass_info := vk.RenderPassBeginInfo{
sType = .RENDER_PASS_BEGIN_INFO,
renderPass = self.render_pass,
framebuffer = self.swapchain_framebuffers[current_image],
renderArea = {offset = {0, 0}, extent = {width = self.framebuffer_width, height = self.framebuffer_height}},
clearValueCount = self.should_clear_depth ? 2 : 1, // use both values only if clearing depth
pClearValues = &clear_values[0],
}
vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
vk.CmdEndRenderPass(command_buffer) // nothing in between: the clear happens by itself
}

//VulkanFinish - last layer , moves the image to the present layout 
VulkanFinish :: struct { 
using renderer: Renderer, 
} 

vulkan_finish_init :: proc(self: ^VulkanFinish, vk_dev: ^VulkanRenderDevice, depth_texture: VulkanImage) -> bool {
renderer_base_init(&self.base, vk_dev, depth_texture)
self.fill_command_buffer = vulkan_finish_fill_command_buffer
self.destroy = renderer_destroy_base_only

ok: bool
self.render_pass, ok = create_color_and_depth_render_pass(
vk_dev.device, depth_texture.image != 0,
RenderPassCreateInfo{clear_color = false, clear_depth = false, flags = {.Last}}, // Last = end of the frame, must not clear or u won't see anything 
)
if !ok {
fmt.println("VulkanFinish: failed to create render pass")
return false
}
self.swapchain_framebuffers, ok = create_color_and_depth_framebuffers(
vk_dev, self.render_pass, depth_texture.view, self.framebuffer_width, self.framebuffer_height,
)
return ok
}

// same as Clear but with no clear values. 
vulkan_finish_fill_command_buffer :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, current_image: u32) {
self := cast(^VulkanFinish)r
render_pass_info := vk.RenderPassBeginInfo{
sType  = .RENDER_PASS_BEGIN_INFO,
renderPass  = self.render_pass,
framebuffer = self.swapchain_framebuffers[current_image],
renderArea  = {offset = {0, 0}, extent = {width = self.framebuffer_width, height = self.framebuffer_height}},
}
vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
vk.CmdEndRenderPass(command_buffer)
}

// ModelRenderer - the duck from 012 as a layer 
/* A more general version of what we did by hand in 012 (VulkanState + draw_overlay), One ModelRenderer owns a mesh (vertices + indices in ONE storage buffer) and ONE texture,
Limiting a model to a single texture keeps this chapter simple and proper materials come in chapter 7. It also lets us render several models in one scene, but it isn't efficient for lots of meshes*/

ModelRenderer :: struct {
using renderer: Renderer, // keep always FIRST
mesh: MeshBuffer, // vertices + indices in one storage buffer (from 011 of chapter 2)
texture: VulkanImage,
texture_sampler: vk.Sampler,
}

/* model_renderer_init builds everything , it takes the shader fiels as arguments , passes "" as geom_shader_file if we don't want to see a geometry shader 
, i think there are some SPIR-V files (.spv) as in 012 or in Assets folder */ 

model_renderer_init :: proc ( 
self : ^ModelRenderer , 
vk_dev : ^VulkanRenderDevice ,
model_file : cstring , 
texture_file : string , 
uniform_data_size : string ,
vert_shader_file : string , 
frag_shader_file : string , 
geom_shader_file : string ,  ) -> bool { 
//the base starts with an empty depth image , ModelRenderer creates the depth buffer itself furthur down the line 
renderer_base_init(&self.base , vk_dev , VulkanImage{}) 
self.fill_command_buffer = model_renderer_fill_command_buffer 
self.destroy = model_renderer_destroy 
ok : bool 

// 1 - load mesh , we reuse the mesh loading code from chapter 2 in create_texture_vertex_buffer in 011/012 
self.mesh, ok = create_textured_vertex_buffer(
vk_dev.device, vk_dev.physical_device, vk_dev.command_pool, vk_dev.graphics_queue, model_file,
)
if !ok {
fmt.println("ModelRenderer: create_textured_vertex_buffer failed")
return false
}

// 2 - the texture image, image view and sampler, also from chapter 3
if !create_texture_image(
vk_dev.device, vk_dev.physical_device, vk_dev.command_pool, vk_dev.graphics_queue,
texture_file, &self.texture.image, &self.texture.memory,
) { return false }
self.texture.view, ok = create_image_view(vk_dev.device, self.texture.image, .R8G8B8A8_UNORM, {.COLOR})
if !ok { return false }
self.texture_sampler, ok = create_texture_sampler(vk_dev.device)
if !ok { return false }

// 3 - finally the depth buffer , VulkanClear and VulkanFinish get it from us later (model.depth_texture) so all layers share it 
self.depth_texture.image , self.depth_texture.memory , self.depth_texture.view , ok = create_depth_resources ( 
vk_dev , self.framebuffer_width , self.framebuffer_height , ) 
if !ok { return false } 

// 4 - uniform buffers (one per swapchain image) - see renderer_create_uniform_buffers
if !renderer_create_uniform_buffers(&self.base, vk_dev, uniform_data_size) { return false }


/* 5 - descriptor pool + sets - Pool sizes per image: 1 uniform buffer, 2 storage buffers (vertices + indices), 1 sampler
create_descriptor_set (from 011) is exactly the book's ModelRenderer::createDescriptorSet. Its four bindings -
0 = uniform buffer (the mvp matrix) vertex stage
1 = storage buffer (vertices) vertex stage
2 = storage buffer (indices) vertex stage
3 = combined image sampler (the texture) fragment stage
The mesh data never changes, so this only needs to run once, here, from the constructor */ 
self.descriptor_pool, ok = create_descriptor_pool(vk_dev.device, u32(len(vk_dev.swapchain_images)), 1, 2, 1)
if !ok { return false }
self.descriptor_set_layout, self.descriptor_sets, ok = create_descriptor_set(
vk_dev.device, self.descriptor_pool, self.uniform_buffers, uniform_data_size,
self.mesh, self.texture_sampler, self.texture.view,
)
if !ok { return false }

// 6 - render pass: empty flags = a MIDDLE layer, It doesn't clear (VulkanClear already did) and it isn't the last pass either (VulkanFinish handles the present layout).
self.render_pass, ok = create_color_and_depth_render_pass(vk_dev.device, true, RenderPassCreateInfo{})
if !ok { return false }

// 7 - pipeline layout + pipeline 
