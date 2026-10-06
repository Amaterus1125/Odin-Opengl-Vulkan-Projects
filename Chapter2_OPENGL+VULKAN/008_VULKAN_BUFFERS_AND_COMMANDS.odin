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



