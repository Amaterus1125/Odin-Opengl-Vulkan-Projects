// WARNING - FROM NOW ON ADDITIONS ONLY (not a standalone file)
// Paste everything below into your existing file from chapter 3, UNDER your existing helper procs.
// There is no `package` line here. If you already have a `main` proc, REPLACE it with the one at the bottom of this file.

// THIS FILE TAKES 011 (MESH BUFFER + DESCRIPTOR SETS) AND COMBINES IT WITH THE "VK02 DEMO APP" RECIPE (rendering the rubber duck).
// PART 1 + PART 2 = the code from 011 
// PART 3 = the NEW for thee demo app, state structs, init_vulkan, fill_command_buffer, draw_overlay, terminate_vulkan, main.

/* IMPORTS - Odin imports can't be pasted in the middle of a file, so make sure these are at the TOP of your file:
	import "core:fmt"
	import "core:mem"
	import "core:os"
	import "core:math/linalg"
	import "vendor:glfw"
	import vk "vendor:vulkan"
	import cgltf "vendor:cgltf"
*/

/* PROCS FROM OLDER FILES THAT THIS FILE CALLS (they must already exist in your file).
I don't have your older files, so the signatures below are my ASSUMPTION and if yours look different, only the call sites inside init_vulkan() need changing.

from 008-010 (already used by 011):  create_buffer, destroy_buffer, copy_buffer, UniformBuffer { mvp: matrix[4,4]f32 }
from chapter 3 initialisation recipes:
	create_instance() -> (vk.Instance, bool)
	setup_debug_callbacks(instance) -> (vk.DebugUtilsMessengerEXT, bool)
	init_vulkan_render_device(^VulkanRenderDevice, instance, surface, width, height, features: vk.PhysicalDeviceFeatures) -> bool
	destroy_vulkan_render_device(^VulkanRenderDevice)
	create_shader_module(device, filename: string) -> (vk.ShaderModule, bool)
	create_texture_image(device, physical_device, command_pool, queue, filename: string, ^vk.Image, ^vk.DeviceMemory) -> bool
	create_image_view(device, image, format, aspect: vk.ImageAspectFlags) -> (vk.ImageView, bool)
	create_texture_sampler(device) -> (vk.Sampler, bool)
	create_depth_resources(^VulkanRenderDevice, width, height) -> (vk.Image, vk.DeviceMemory, vk.ImageView, bool)
	create_color_and_depth_render_pass(device, use_depth: bool, info: RenderPassCreateInfo) -> (vk.RenderPass, bool)
	create_pipeline_layout(device, set_layout) -> (vk.PipelineLayout, bool)
	create_graphics_pipeline(device, width, height, render_pass, pipeline_layout, stages: []vk.PipelineShaderStageCreateInfo) -> (vk.Pipeline, bool)
	create_color_and_depth_framebuffers(^VulkanRenderDevice, render_pass, depth_view, width, height) -> ([]vk.Framebuffer, bool)

And a struct called VulkanRenderDevice (this is "vkDev" in the book) with these fields:
	device, physical_device, graphics_queue, command_pool, command_buffers: []vk.CommandBuffer,
	swapchain, swapchain_images: []vk.Image, semaphore, render_semaphore
*/

// PART 1 - USING MESH FEOMETRY DATA UN VULKAN (FROM 011) 
/* Same programmable vertex pulling (PVP) idea as our OpenGL 008 file, no vertex attributes. The shader gets the raw
vertices AND the raw indices as storage buffers (SSBOs) and looks things up itself, we use cgltf, exactly as in 008. */

VertexData :: struct {
pos: [3]f32,
tc:  [2]f32,
}

/*BUG FIX vs 011: the old struct had a field called `vertex_offset` but the code below writes `mesh.index_size`,
so it would not compile. The correct fields are vertex_size, index_offset and index_size. */
MeshBuffer :: struct {
buffer: vk.Buffer, // one buffer holding vertices first and then indices
memory: vk.DeviceMemory,
vertex_size:  vk.DeviceSize, // size of the vertex section in bytes
index_offset: vk.DeviceSize, // where the index section starts inside the buffer
index_size:   vk.DeviceSize, // size of the index section in bytes
}

STORAGE_OFFSET_ALIGNMENT :: 256

create_textured_vertex_buffer :: proc(
device: vk.Device,
physical_device: vk.PhysicalDevice,
command_pool: vk.CommandPool,
graphics_queue: vk.Queue,
filename: cstring, // "data/rubber_duck/scene.gltf" ) -> (mesh: MeshBuffer, ok: bool) {
options: cgltf.options
data, parse_result := cgltf.parse_file(options, filename)
if parse_result != .success {
fmt.println("Unable to load", filename)
return {}, false
}
defer cgltf.free(data)
if cgltf.load_buffers(options, data, filename) != .success { return {}, false }

// use only the first primitive of the first mesh
prim := data.meshes[0].primitives[0]
pos_acc, tc_acc: ^cgltf.accessor
for attr in prim.attributes {
#partial switch attr.type {
case .position: pos_acc = attr.data
case .texcoord: tc_acc = attr.data
}
}

if pos_acc == nil { return {}, false }
