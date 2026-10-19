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
