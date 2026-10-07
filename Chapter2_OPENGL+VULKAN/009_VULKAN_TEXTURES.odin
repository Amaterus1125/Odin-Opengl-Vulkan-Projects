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




