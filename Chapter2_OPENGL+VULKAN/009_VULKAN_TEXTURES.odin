//common imports and vulkan detection or not thingy
package main

import "core:fmt"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"
import stbi "vendor:stb/image"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}


//PART 1 - CREATING AN IMAGE (the texture equivalent of create_buffer) 
/* A vulkan image is another type of buffer that's designed to store a 1D , 2D or 3D image, so this function is almost odentical in shape to creating create_buffer() from our previous file , 
sa,e "create the object, ask how much memeory it needs , allocate that memory ,bind them together" pattern. the real difference is that images use ckBindImageMemory() instead of vkBindBufferMemory(), since an imahe 
isn't just a flat buffer, it has width/height/format baked into its description */

create_image :: proc( 
device : vk.Device ,
physical_device : vk.PhysicalDevice , 
wigth , height : u32 ,
format : vk.Format ,
tiling : vk.ImageFilling,
usage : vk.ImageUsageFlage,
properties : vk.MemoryPropertyFlags , 
) -> (image : vk.Image , image_memory: vk.DeviceMemory , ok: bool) { 
image_info := vk.ImageCreateInfo{ 
sType = .IMAGE_CREATE_INFO , 
imageType = .D2 , 
format = format , 
extent = {width , height , 1} //depth = 1 , this is a flat image and not a 3d image 
mipLevels = 1 ,
arrayLayers = 1 , 
samples = {._1} , //no multisampling (anti-aliasing) for this image 
tiling = tiling , //how pixels are physically arranged in memory 
usage = usage , 
sharingMode = .EXCLUSIVE . 
initialLayout = .UNDEFINED , // the image starts out with no meangingful layout at all 
} 
if vk.CreateImage(device, &image_info, nil, &image) != .SUCCESS {
return {}, {}, false
}
mem_requirements : vk.MemoryRequirements 
vk.GetImageMemoryRequirements(device , image , &mem_requirements) 

alloc_info := vk.MemoryAllocateInfo{ 
sType = .MEMORY_ALLOCATE_INFO , 
allocationSize = mem_requirements.size , 
memoryTypeIndex = find_memory_type(physical_device , mem_requirements.memoryTypeBits , properties),
}
if vk.AllocateMemory(device, &alloc_info , nil , &image_memory) != .SUCCESS {
 return {}, {} , false 


if vk.CreateImage(device, &image_info, nil, &image) != .SUCCESS {
		return {}, {}, false
	}
// PART 2: THE TEXTURE SAMPLER
/* Having the pixel data sitting in GPU memory isn't enough on its own, a fragment shader does not read raw memory directly , it asks a sampler object for a color at a giveb (u,v) coordinate,
and the sampler is what decides how to answer that, do we blend neighboring pixels together (filtering) or just grab the closest one ? , what happens if the coordinate goes past the edge of the image (wrapping , clamping etc)? ,
all of that behaviour lives in this one sampler object completly seperate from the image/pixel data itself */ 

create_texture_sampler :: proc(device: vk.Device) -> (sampler: vk.Sampler, ok : bool) { 
sampler_info := vk.SamplerCreateInfo{ 
sType = .SAMPLER_CREATE_INFO, 
magFilter = .LINEAR , //when the texture is shown bigger than its real resolution, blend neighbouring pixels smoothly 
minFilter = .LINEAR ,  //same , but for when it's shown smaller 
mipmapMode = .LINEAR , 
addressModeU = .REPEAT , // what happens past the edge of the texture , repeat just tiles over and over 
addressModeV = .REPEAT ,
addressModeW = .REPEAT , 
maxAnisotropy = 1 , 
borderColor = .INT_OPAQUE_BLACK , 
compareOp = .ALWAYS , 
} 
result := vk.CreateSampler(device , &sampler_info , nil , &sampler) 
return sampler , result == .SUCCESS 

// copying buffer data into an image - 
/* same general idea as copy_buffer() from the previous file (a one shot command buffer that runs a copy and waits for it) , except this variant copies
from a flat buffer into a structured image , so it needs to describe width/height/which part of the image , instead od just a byte count 

copy_buffer_to_image :: proc(device: vk.Device , command_pool : vk.CommandPool , graphics_queue: vk.Queue , buffer: vk.Buffer , image : vk.Image , width , height : u32) { 
cb := begin_single_time_commands(device , command_pool) 
region := vk.BufferImageCopy{ 
bufferOffset =0 , 
bufferRowLength = 0 , // 0 means tightly packed and no extra padding between rows 
imageSubresource = {aspectMask = {.COLOR} , mipLevel = 0 , baseArraylayer = 0 , layerCount = 1} ,
imageOffset = {0,0,0} , 
imageExtent = {width , height , 1 } ,
} 
vk.CmdCopyBufferToImage( cb , buffer , image , .TRANSFER_DST_OPTIMAL , 1 , &region) 
end_single_time_commands(device , command_pool , graphics_queue , cb) 
} 

//PART 3 - IMAGE LAYPUT TRANSITIONS 



