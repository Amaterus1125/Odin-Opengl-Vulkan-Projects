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


