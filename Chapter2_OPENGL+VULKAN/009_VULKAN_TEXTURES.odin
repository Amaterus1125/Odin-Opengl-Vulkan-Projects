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
from a flat buffer into a structured image , so it needs to describe width/height/which part of the image , instead of just a byte count */

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
/* on the gpu , it is often faster to store an image pixel in a special, rearranged internal order rather than a plain predictable grid, the gpu can access that rearranged layout more 
 effiiently depending on what's its currently being used for (being written to , being read from in a shader , being presented on the screen) ,vulkan calls this arrangement the image "layout" and vulkan makes 
 us explicitly declare about that we are about to switch from usinf this image as a copy destination to using it as something a shader reads from , this declaration is called a "pipeline barrier" and doing one is called a "layout transition"

 if we skip this , our validation layer will warn us , so doing these transitions correctly is also a good practice for avoiding mysterious bugs on other people gpu's later */ 

transition_image_layout_cmd :: proc(command_buffer: vk.CommandBuffer, image : vk.Image , format : vk.Format , old_layout , new_layout : vk.ImageLayout , layer_count , mip_levels: u32){
  barrier := vk.ImageMemoryBarrier{
    sType  = .IMAGE_MEMORY_BARRIER , 
    oldLyout = old_layout , 
    newLayout = new_layout , 
    srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED , // we are not transffering ownership between different queue families , just changing layout 
    dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED , 
    image = image , 
    subresourceRange = { aspectMask  = {.COLOR} , baseMipLevel = 0 , levelCount = 1 , baseArraylayer = 0 , layerCount = 1},
  }

  //a depth buffer needs a different "aspect mask" than a normal color image , we are reading . writing its depth balues and not rgba colors 
  if new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL { 
  barrier.subresourceRange.aspectMask = {.DEPTH } 
  if has_stencil_component(format) {
    barrier.subresourceRange.aspectMask |= {.STENCIL}
  }
  } else {
    barrier.subresourceRange.aspectMask = {.COLOR}
  }

  source_stage , destination_stage : vk.PipelineStageFlags 

 
  /*each pf the 3 cases below answers the same 2 questions for specific situations , "what kinf of memory access was happening before this transition" (srcAccessMask) and 
   * "what kind of access is about to happen after it " (dstAccessMask) , this is what lets the gpu correctly order its own internal work around the change */ 

  if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL { 
  // case - a brand new image , about to be written into via a copy (like right after create_imahe and before copy_buffer_to_image)
  barrier.srcAccessMask= { }
  barrier.dstAccessMask = {.TRANSFER_WRITE}
  source_stage = {.TOP_OF_PIPE}
  destination_stage = {.TRANSFER}
  } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL { 
  // case: we just finished copying pixel data in, and now a
		// fragment shader wants to actually sample from this texture
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}
		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		// case: a brand new depth buffer, about to be used for depth testing
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}
		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.EARLY_FRAGMENT_TESTS}
	}
  // this is the actual command that tells the gpu to pause here and wait for everything in source_stage to finish , then let destination_stage proceed , a pipeline barrier is genuinly hust a synchronization checkpoint plus a layout change bundles together 
  vk.CmdPipelineBarrier(command_buffer , source_stage, destination_stage, {} , 0 , nil , 0 , nil , 1 , &barrier)

}

transition_image_layout :: proc(device : vk.Device , command_pool : vk.CommandPoll,graphics_queue: vk.Queue, image: vk.Image, format: vk.Format, old_layout, new_layout: vk.ImageLayout) { 
 cb := begin_single_time_commands(device, command_pool)
 transition_image_layout_cmd(cb , image , format , old_layout , new_layout , 1 ,1 )
 end_single_time_commands(device , command_pool , graphics_queue , cb )
}

// THE VULKAN TEXTURE bundle 
// a usable texture is really 3 seperate vulkan objects working together , the raw image data , the memory backing it , and a view describing how to read it 
// and bundling all 3 into one struct means we only need to pass around (and clean up )  one thing from here on 
VulkanTexture :: struct { 
  image : vk.Image , 
  image_memory : vk.DeviceMemory , 
  image_view : vk.ImageView ,
}

destroy_vulkan_texture :: proc(device: vk.Device, texture: ^VulkanTexture) {
	vk.DestroyImageView(device, texture.image_view, nil)
	vk.DestroyImage(device, texture.image, nil)
	vk.FreeMemory(device, texture.image_memory, nil)
}

// PART 4 - DEPTH BUFFER SUPPORT 
// a depth support needs a specific numeric format the GPU can actually use for depth comparions , but not every gpu supports every depth format equally 
// these 3 functions ask the gpu "out of these candidate formats , which one do you actually support for this purpose , rather than just hardcoding a guess that might fail in someone else hardware "

find_supported_format :: proc(device: vk.PhysicalDevice, candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {
for format in candidates { 
  props: vk.FormatProperties 
  vk.GetPHysicalDeviceFormatProperties(device , format , &props )
  if tiling == .LINEAR && (props.linearTilingFeatures & features) == features { 
   return format 
  }
  if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format
		}
}
fmt.println("FAILED TO FIND SUPPORTED FORMAT FOR THE FILE")
panic("NO SUPPORTED DEPTH FORMAT")
}

find_depth_format :: proc(device : vk.PhysicalDevice) -> vk.Format { 
  candidates := []vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}
	return find_supported_format(device, candidates, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

has_stencil_component :: proc(format : vk.Format) -> bool {
  return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

create_depth_resources :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, command_pool: vk.CommandPool, graphics_queue: vk.Queue, width, height: u32) -> (depth: VulkanTexture, ok: bool) {
	depth_format := find_depth_format(physical_device)

	image, image_memory, created := create_image(device, physical_device, width, height, depth_format, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL})
	if !created { return {}, false }
	depth.image = image
	depth.image_memory = image_memory

	view, view_ok := create_image_view(device, depth.image, depth_format, {.DEPTH})
	if !view_ok { return depth, false }
	depth.image_view = view

	// a freshly created depth image starts in an UNDEFINED layout and needs to be transitioned before the gpu can actually use it for depth testing  same idea explained in Part 3
	transition_image_layout(device, command_pool, graphics_queue, depth.image, depth_format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL)

	return depth, true
}

// PART 5 - LOADING A REAL 2D TEXTURE FROM A FILE - TYING EVERYTHING ABOVE TOGETHER 
/* this is the complete pipeline , load the pixels off disk with stb_image (library) -> copy them into a cpu visible staging buffer -> create the real gpu-only image 
 * -> transition it so it's ready to receive a copy -> copy the pixels in -> transiton it AGAIN so a shader is allowed to read from it , two transitions beacuse an image layout requirement is different at each stage of this process 
 */ 

create_texture_image ::proc(device: vk.Device, physical_device: vk.PhysicalDevice, command_pool: vk.CommandPool, graphics_queue: vk.Queue, filename: cstring) -> (image: vk.Image, image_memory: vk.DeviceMemory, ok: bool) {
  tex_width , tex_height , tex_channels : i32 
  pixels := stbi.load(filename , &tex_width , &tex_height , &tex_channels , 4) // force 4 channels rgba regardless of the source file actual channel count , so our code below can assume a fixed layout 
  if pixels == nil {
		fmt.println("Failed to load [", filename, "] texture")
		return {}, {}, false
	}
	defer stbi.image_free(pixels)
image_size := vk.DeviceSize(tex_width * tex_height * 4)

// a staginf buffer is necessary here for the same reason as out earlier buffer recipe , the gpu local memory an imae ultimately wants to live in usuallt can't be written to directly from cpu, so we first write into plain cpu visible memory , then let the gpu copy it over on it's own 
staging_buffer , staging_memory , staging_ok := create_buffer(device , physical_device , image_size , {.TRANSFER_SRC} , {.HOST_VISIBLE , .HOST_COHERENT})
if !staging_ok { return {}, {}, false }
defer destroy_buffer(device, staging_buffer, staging_memory)
data : rawptr 
vk.MapMemory(deive , staging_memory , 0 , image_size , {} , &data)
mem.copy(data , pixels , int(image_size))
vk.UnmapMemory(device , staging_memory)
created : bool 
image, image_memory, created = create_image(device, physical_device, u32(tex_width), u32(tex_height), .R8G8B8A8_UNORM, .OPTIMAL, {.TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL})
if !created { return {}, {}, false }

// step 1 - get the fresh image ready to receive a copy 
transition_image_layout(device, command_pool, graphics_queue, image, .R8G8B8A8_UNORM, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
// step 2: actually copy the pixel data in
copy_buffer_to_image(device, command_pool, graphics_queue, staging_buffer, image, u32(tex_width), u32(tex_height))
// step 3: get the now-filled image ready to be READ by a shader
transition_image_layout(device, command_pool, graphics_queue, image, .R8G8B8A8_UNORM, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)

return image, image_memory, true

}


