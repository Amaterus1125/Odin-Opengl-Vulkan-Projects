package main

import "core:fmt"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}

// PART 1 - DEALING WITH BUFFERS IN VULKAN 
/* buffers in vulkan are regions of memory that store data that can be rendered on the GPU , in plain erms a buffer is just a block of memory living on our gpu that we could put stuff in 
like vertex positions , textures , matrices etc.
the tricky part is in vulkan we have to deal with them unlike in opengl which actually hides them from us and gpu hvae many types of memory, gpu has several different "heaps" with different trade-offs, 
some memories are fast for the gpu but the cpu can't write to it directly, some memory is slower but our cpu can write on it, we have to select which type of memory to use.
*/

/* the below code walks through every memeory type this gpu has to offer and returns index of the first one that both - 
1. is allowed by type-filter ( a bitmask the gpu itself gaveus saying which memory type a particular buffer is allowed to use) 
2. actually has the properties we asked for ( like must be writable directly from the cpu)  */
find_memory_type :: proc(physical_device : vk.PhysicalDevice , type_filtee: u32 , properties: vk.MemoryPropertyFlags) -> u32 { 
mem_properties : vk.PhysicalDeviceMemoryProperties 
vk.GetPhysicalDeviceMemoryProperties(physical_device , &mem_properties) 

for i in 0 ..< mem_properties.memoryTypeCount { 
bit := u32(1) << i 
type_allowed := (type_filter & bit) != 0 
has_properties := memproperties.memoryTypes[i].propertyFlags & properties == properties 
if type_allowed && has_properties { 
return i 
} } 
return 0xFFFFFFFF    // not found , in real code we did want to treat this as an error 
} 

/* the below code creates a buffer object and the actual chunk of gpu memory backing it and then conencts the two, this one function is reused for every different kind of buffer we will ever need (uniform buffers, staging buffers , vertex buffers etc 
and what makes them different is just which usage and properties flags gets passed in */ 

create_buffer :: proc( 
device : vk.Device 
physical_device: vk.PhysicalDevice , 
size: vk.DeviceSize,
usage : vk.BufferUsageFlags , 
properties : vk.MemoryPropertyFlags , )  -> (buffer: vk.Buffer , buffer_memory: vk.DeviceMemory , ok : bool) { 
buffer_info := vk.BufferCreateInfo { 
sType := .BUFFER_CREATE_INFO, 
size = size , 
usage = usage , 
sharingMode = .EXCLUSIVE , // only one queue family will touch this buffer at a time , helps us to make it simpler and faster than sharing it between several 
}
if vk.CreateBuffer(device , &buffer_info , nil , &buffer) != .SUCCESS { 
return {} , {} , false 
} 

//creating the buffer above does not actually give it any memory yet , its just a description , we now ask vulkan to give what i asked for and how much memory does this actually need and memory which memory types are we allowed to use 
mem_requirements : vk.MemoryRequirements 
vk.GetBufferMemoryRequirements(device , buffer , &mem_requirements) 

alloc_info := vk.MemoryAllocateInfo{ 
sType : .MEMORY_ALLOCATE_INFO, 
allocationSize = mem_requirements.size,
memoryTypeIndex = find_memory_type(physical_device , mem_requirements.memoryTypeBits , properties) ,
}
if vk.AllocateMemory(device , &alloc_info , nil , &buffer_memory) != .SUCCESS { 
return {} , {} , false 
} 

vk.BindBufferMemory(device , buffer , buffer_memory , 0 ) 
return buffer , buffer_memory , true 
} 

destroy_buffer :: proc(device: vk.Device , buffer: vk.Buffer , buffer_memory: vk.DeviceMemory) { 
vk.DestroyBuffer(device , buffer , nil) 
vk.FreeMemory(device , buffer_memory , nil) 
} 

// SINGLE TIME COMMANDS - a temperary command buffer used for exactly ONE job , then thrown away , useful at times when we need the gpu to do something right now and wait for it , rather than it being part of our normal per-frame rendering work 

begin_single_time_commands :: proc(device: vk.Device , command_pool: vk.Command_Pool)  -> vk.CommandBuffer { 
alloc_info := vk.CommandBufferAllocateInfo{ 
sType = .COMMAND_BUFFER_ALLOCATE_INFO , commandPool = command_pool , 
level = .PRIMARY , commandBufferCOunt = 1, 
} 
command_buffer : vk.COmmandBuffer 
vk.AllocateCommandBuffers(device , &alloc_info , &command_buffer) 
begin_info := vk.COmmandBufferBeginInfo{ 
sType = .COMMAND_BUFFER_BEGIN_INFO , 
flags = { .ONE_TIME_SUBMIT} ,  // tells the vulkan that we are oly going to submit this buffer once and it should optimize for that 
} 
vk.BeginCommandBuffer(command_buffer , &begin_info) 
return command_buffer 
} 

/* now after that finishes recording , submits the command buffer to the GPU and then waits right here until the gpu has actually finished running it, that wait is the unsrual and important part , our normal per frame rendering never waits like this 
but for one off setup task like "upload this data" waiting is exactly what we want so we know it's safe to use the result immediatly after */

end_single_time_commands :: proc(device : vk.Device , command_pool: vk.CommandPoll , grphics_queue: vk.Queue , command_buffer = vk.CommandBuffer ) { 
cb := command_buffer 
vk.EndCommandBuffer(cb) 
submit_info := vk.SubmitInfo{ 
sType = .SUBMIT_INFO , commandBufferCount = 1 , pCommandBuffers = &cb , 
} 
vk.QueueSubmit(graphics_queue , 1 , &submit_info , {})
vk.QueueWaitIdle(graphics_queue)  // the actual wait until the gpu is donw part 
vk.FreeCommandBuffers(device , command_pool , 1 &cb) 
} 

/* the below code copies data from one gpu buffer straight into another , gpu-side without the cpu ever touching the actual bytes , this is exactly how we later get vertex/index data 
from a cpu writable "staging" uffer into a fast gpu-only buffer the gpu can actually render from */
copy_buffer :: proc(device: vk.Device, command_pool: vk.CommandPool, graphics_queue: vk.Queue, src, dst: vk.Buffer, size: vk.DeviceSize) {
cb := begin_single_time_commands(device, command_pool) 
copy_region := vk.BufferCopy{srcOffset =0 , dstOffset = 0 , size = size } 
vk.CmdCopyBuffer(cb , src , dst , 1 , &copy_region) 
end_single_time_commands(device , command_pool , graphics_queue , cb) 
} 

/* UNIFORM BUFFERS - a small buffer holding data that stays the same for every vertex/pixel for one draw call , our MVP matrix is the classic example as every vertex in a mesh gets multiplied by the exact same MVP, 
so it makes sense to store it once , seperately , rather than repeating it per vertex */

UniformBuffer :: struct { 
mvp : matrix[4,4]f32 ,
} 
/* one uniform buffer gets created per swapchain image because different swapchain images can be in "flight" (still being used by gpu) at overlapping times , each needs is own 
copy of this frame data so we don't accidently overwrite data the gpu has not finished reading yet */ 
create_uniform_buffers :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, image_count: int) -> (buffers: []vk.Buffer, buffers_memory: []vk.DeviceMemory, ok: bool) {
buffer_size := vk.DeviceSize(size_of(UniformBuffer))
buffers = make([]vk.Buffer , image_count) 
buffers_memory = make([]vk.DeviceMemory , image_count) 

for i in 0..< image_count { 
// HOST_VISIBLE = the cpu is actually allowed to write into this memory directly 
//HOST_COHORENT = we don't need to manually flush our writes ,they become visible to the gpu automatically 
//this combination trades a little gpu-side speed for the convieneice of writing to it plainly every frame , which is right call for small, frequently-updated data like this 
buf , buf_mem , success := create_buffer(device , physical_device , buffer_size , {.UNIFORM_BUFFER}, {.HOST_VISIBLE , .HOST_COHERENT}) 
if !success {
	fmt.println("Fail: buffers")
	return buffers, buffers_memory, false
}
	buffers[i] = buf
	buffers_memory[i] = buf_mem
	}
return buffers, buffers_memory, true
}

//called ebry frame to push this frame data (like freshly computed MVP matrix) into one specific uniform buffer 
update_uniform_buffer :: proc(device: vk.Device, buffer_memory: vk.DeviceMemory, ubo: UniformBuffer) {
ubo_local := ubo //odin can't take the address of a plain parameter , so we copy it into a local variable first 
data : rawptr   
//map the memory - temporarily get a regular cpu pointer we are allowed to write into , even though the memory physically lives on the gpu 
vk.MapMemory(device , buffer_memory , 0 , vk.DeviceSize(size_of(UniformBuffer)) , {} , &data) 
mem.copy(data , &ub0_local, size_of(UniformBuffer) ) //plain byte copy , 
vk.UnmapMemory(device , buffer_memory) //give our cpu pointer , the gpu is now free to use this memory again 
} 

//PART - 2 USING VULKAN COMMAND BUFFERS , FILLINF ONE WITH ACTUAL DRAWING COMMANDS 
/*Quick heads-up before this one: the book's version of this function assumes you already have a RENDER PASS, FRAMEBUFFERS, and a GRAPHIC'S PIPELINE set up none of which we've built yet (those are later recipes in the book). So this function is written to take all of that as PARAMETERS, so it's fully correct and ready to use the moment we
 build those pieces, rather than silently referencing things tha don't exist. We won't actually CALL this function yet in main() for that same reason. */
fill_command_buffer :: proc(
command_buffer: vk.CommandBuffer , 
render_pass: vk.RenderPass, 
framebuffer : vk.FrameBuffer , 
pipeline : vk.Pipeline , 
pipeline_layout : vk.PipelineLayout , 
descriptor_set : vk.DescriptorSet,
screem_width , screen_height : u32, 
clear_color : [4]f32,
vertex_count: u32, ) -> bool { 
begin_info := vk.CommandBufferBeginInfo{ 
sType = .COMMAND_BUFFER_BEGIN_INFO, 
flags = {.SIMULTANEOUS_USE) , // this buffer is allowed to be submitted again while a previous submission might still be running 
} 

vk_check(vk.BeginCommandBuffer(command_buffer , &begin_info) , "beignning command buffer") 

//next code is abt what to reset the screen to before drawing , one value for actual picture (color) , one for the depth buffer (used to figure out which pixels are in front of others) 
clear_values := [2]vk.ClearValue{ 
{color = {float32 = clear_color}} ,
{depthStencil = {depth = 1.0 , stencil = 0}} , } 
screen_rect := vk.Rect2D{offset = {0,0} , extent = {screen_width , screen_height} } 

//a render pass describes the overall plan for this drawing operation (what gets cleared, what format the output is etc, beigning one tells the gpu everything between here and CmdEndRenderPass belongs to this one drawing operation 
render_pass_info := vk.RenderPassBeginInfo{ 
sType = .RENDER_PASS_BEGIN_INFO, 
render_pass_info := vk.RenderPassBeginInfo{ 
sType = .RENDER_PASS_BEGIN_INFO, 
renderPass = render_pass , 
framebuffer , framebuffer , //which actual image we are drawing into this time 
renderArea = screen_rect , 
clearValueCount = 2 , 
pClearValues = &clear_values[0] , 
} 
vk.CmdBeginRenderPass9command_buffer , &render_pass_info , .INLINE) 
// bind 0 from now on , ise this one , the pipeline budles up the vertex/fragment shaders plus a big pile of fixed function gpu settings, into one usable object 
vk.CmdBindPipeline9command_buffer , .GRAPHICS , pipeline) 

// descriptor sets are how buffers/textures (like our uniform buffer from part 1) actually get connected to a shader at draw time 
ds := descriptor_set 
vk.CmdBindDescriptorSets(command_buffer , .GRAPHICS , pipeline_layout , 0 , 1 , &ds , 0 , nil) 

/* the above is the actual drew somethings command ,this calls the plain (non-indexed) CmdDraw, with a vertex count computed from what WOULD be an index buffer's size that's not a mistake, it's the SAME programmable-vertex-pulling
 trick from our earlier 008 file: the vertex shader manually looksup each vertex using gl_VertexID equivalent logic, so a normal "index buffer" isn't bound here the usual way */ 

vk.CmdDraw(command_buffer , vertex_count, 1 , 0 , 0) 
vk.CmdEndRenderPass(command_buffer) 
return vk.EndCommandBuffer(command_buffer) == .SUCCESS 

// REUSED SETUP FROM THE PREVIOUS FILES
create_instance :: proc() -> vk.Instance {
	layers := []cstring{"VK_LAYER_KHRONOS_validation"}
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	app_info := vk.ApplicationInfo{sType = .APPLICATION_INFO, pApplicationName = "Vulkan", apiVersion = vk.API_VERSION_1_1}
	create_info := vk.InstanceCreateInfo{
		sType = .INSTANCE_CREATE_INFO, pApplicationInfo = &app_info,
		enabledLayerCount = u32(len(layers)), ppEnabledLayerNames = raw_data(layers),
		enabledExtensionCount = u32(len(glfw_extensions)), ppEnabledExtensionNames = raw_data(glfw_extensions),
	}
	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "creating instance")
	vk.load_proc_addresses(instance)
	return instance
}

find_suitable_physical_device :: proc(instance: vk.Instance, selector: proc(device: vk.PhysicalDevice) -> bool) -> (vk.PhysicalDevice, bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 { return {}, false }
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	for device in devices { if selector(device) { return device, true } }
	return {}, false
}

find_queue_families :: proc(device: vk.PhysicalDevice, desired_flags: vk.QueueFlags) -> u32 {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))
	for family, i in families {
		if family.queueCount > 0 && (family.queueFlags & desired_flags == desired_flags) { return u32(i) }
	}
	return 0
}

create_device :: proc(physical_device: vk.PhysicalDevice, device_features: vk.PhysicalDeviceFeatures, graphics_family: u32) -> (vk.Device, vk.Result) {
	extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	queue_priority: f32 = 1.0
	queue_info := vk.DeviceQueueCreateInfo{sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = graphics_family, queueCount = 1, pQueuePriorities = &queue_priority}
	features_local := device_features
	create_info := vk.DeviceCreateInfo{
		sType = .DEVICE_CREATE_INFO, queueCreateInfoCount = 1, pQueueCreateInfos = &queue_info,
		enabledExtensionCount = u32(len(extensions)), ppEnabledExtensionNames = raw_data(extensions),
		pEnabledFeatures = &features_local,
	}
	device: vk.Device
	result := vk.CreateDevice(physical_device, &create_info, nil, &device)
	return device, result
}


// MAIN demonstrates the buffer/memory functions from Part 1 (these genuinely work standalone). fill_command_buffer from Part 2 is left unused here on purpose, as explained above


main :: proc() {
	glfw.Init()
	defer glfw.Terminate()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(800, 600, "Vulkan Buffers", nil, nil)
	defer glfw.DestroyWindow(window)
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	instance := create_instance()
	defer vk.DestroyInstance(instance, nil)

	surface: vk.SurfaceKHR
	vk_check(glfw.CreateWindowSurface(instance, window, nil, &surface), "creating window surface")
	defer vk.DestroySurfaceKHR(instance, surface, nil)

	physical_device, found := find_suitable_physical_device(instance, proc(device: vk.PhysicalDevice) -> bool {
		family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
		return family_count > 0
	})
	if !found { fmt.println("no suitable gpu found"); return }

	graphics_family := find_queue_families(physical_device, {.GRAPHICS})
	device_features: vk.PhysicalDeviceFeatures
	device, dev_result := create_device(physical_device, device_features, graphics_family)
	vk_check(dev_result, "creating logical device")
	defer vk.DestroyDevice(device, nil)
	vk.load_proc_addresses(device)

	graphics_queue: vk.Queue
	vk.GetDeviceQueue(device, graphics_family, 0, &graphics_queue)

	pool_info := vk.CommandPoolCreateInfo{sType = .COMMAND_POOL_CREATE_INFO, queueFamilyIndex = graphics_family}
	command_pool: vk.CommandPool
	vk_check(vk.CreateCommandPool(device, &pool_info, nil, &command_pool), "creating command pool")
	defer vk.DestroyCommandPool(device, command_pool, nil)

	// --- DEMO 1: uniform buffers ---
	// pretend we have 2 swapchain images for this demo
	ubo_buffers, ubo_memory, ubo_ok := create_uniform_buffers(device, physical_device, 2)
	if !ubo_ok { fmt.println("failed to create uniform buffers"); return }
	defer for i in 0 ..< len(ubo_buffers) { destroy_buffer(device, ubo_buffers[i], ubo_memory[i]) }

	my_mvp := UniformBuffer{mvp = 1} // "1" here fills the matrix as an identity matrix -- no transform, just a placeholder
	update_uniform_buffer(device, ubo_memory[0], my_mvp)
	fmt.println("uniform buffers created and updated successfully")

	// --- DEMO 2: staging buffer -> device-local buffer, via copy_buffer ---
	// this is the exact pattern you'd use to upload real vertex data:
	// write into cpu-visible memory, then let the gpu copy it into
	// faster gpu-only memory
	sample_data := [4]f32{1.0, 2.0, 3.0, 4.0}
	data_size := vk.DeviceSize(size_of(sample_data))

	staging_buf, staging_mem, _ := create_buffer(device, physical_device, data_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer destroy_buffer(device, staging_buf, staging_mem)

	mapped: rawptr
	vk.MapMemory(device, staging_mem, 0, data_size, {}, &mapped)
	mem.copy(mapped, &sample_data, int(data_size))
	vk.UnmapMemory(device, staging_mem)

	gpu_buf, gpu_mem, _ := create_buffer(device, physical_device, data_size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL})
	defer destroy_buffer(device, gpu_buf, gpu_mem)

	copy_buffer(device, command_pool, graphics_queue, staging_buf, gpu_buf, data_size)
	fmt.println("staging buffer successfully copied into gpu-local buffer")
}
