// the basic imports 
package main

import "base:runtime"
import "core:fmt"

import "vendor:glfw"
import vk "vendor:vulkan"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}

/*PART 1 - THE DEBUG CALLBACKS 
these 2 functions below won't get called by us , vulkan's validation layer calls them automatically on it's own whenever it spots 
a mistake. our job is just to tell it "when that happens , run this code" which we do in setup_debug_callbacks */

// the modern general purpose one - just prints whatever message vulkan gives us 
vulkan_debug_callback :: proc "c" { 
message_severity : vk.DebugUtilsMessageSeverityFlagsEXT,
message_type : vk.DebugUtilsMessageTypeFlagsEXT , 
callback_data : ^vk.DebugUtilsMessangerCallbackDataEXT,
user_data : rawptr , 
) -> b32 { 
 context = runtime.default_context() // required anytime a C callback needs to use normal odin code (like fmt here) 
 fmt.println("Validation Layer:" , callback_data.pMessage) 
return false 
} 

/* the older more detaield one - also tells us which vulkan object caused the issue, which is useful for tracking down exactly what you misconfigured, we skip printing pure performance 
warnings so the output doesn't get too noisy to actually read */

vulkan_debug_report_callback :: proc "c" (
flags: vk.DebugReportFlagsEXT,
object_type : vk.DebugReportObjectTypeEXT , 
object : u64
location : int , 
message_code : i32 ,
layer_prefix: cstring , 
message : cstring , 
user_data: rawptr, 
) -> b32 { 
context = runtime.default_context() 
 if .PERFORMANCE_WARNING in flags { 
return false } 
fmt.println("Debug callbacks (" , layer_prefix, "):" , message) 
 return false 
} 

// registers both callbacks above with vulkan, this is the part that actually turns them on 
setup_debug_callbacks :: proc(instance:vk.Instance) -> (messenger: vk.DebugUtilsMessengerEXT , report_callback: vk.DebugReportCallbackEXT) { 
  messenger_info := vk.DebugUtilsMessengerCreateInfoEXT{ 
 sType = .DEBUG_UTILS-MESSENGER-CREATE-INFO-EXT, 
 messageSeverity = {.WARNING , .ERROR} ,
messageType = {.GENERAL , .VALIDATION , .PERFORMANCE} , 
pfnUserCallback = vulkan_debug_callback , 
} 
vk_check(vk.CreateDebugUtilsMessengerEXT(instance , &messenger_info , nil , &messenger) , "creating debug messenger") 

report_info := vk.DebugReportCallbackCreateInfoExt{ 
 sType = .DEBUG_REPORT_CALLBACK_INFO_EXT , 
 flags = {.WARNING , .PERFORMANCE_WARNING , .ERROR , .DEBUG } 
pfnCallback = vulkan_debug_report_callback, 
} 
vk_check(vk.CreateDebugReportCallbackEXT(instance , &report_info , nil , &report_callback) , "creating debug report callback") 
return 
} 

//PART -2 
/* instead of a pile of loose variables , everything related to our connectio to vulkan itself, lives in one struct, and everything related to our actual gpu and its resources lives in another  */
VulkanInstance :: struct { 
instance: vk.Instance , 
surface: vk.SurfaceKHR,
messenger: vk.DebugUtilsMessengerEXT,
report_callback: vk.DebugReportCallbackEXT,
}

VUlkanRenderDevice :: struct { 
 device:  vk.Device, 
graphics_queue: vk.Queue, 
physical_device: vk.PhysicalDevice , 
graphics_family : u32, 
semaphore: vk.Semaphore  ,  // signals that the swapchain image is ready to be rendered into 
render_semaphore: vk.Semaphore , // signals that the rendering is finished , safe to present now 
swapchain: vk.SwapchainKHR ,
swapchain_images : []vk.Image,
swapchain_image_views: []vk.ImageView,
command_pool: vk.CommandPool , 
command_buffers: []vk.CommandBuffer,
}

create_semaphore :: proc(device: vk.Device) -> (vk.Semaphore, vk.Result) {
info := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
sem: vk.Semaphore 
result := vk.CreateSemaphore(device , &info , nil , &sem) 
return sem , result 
}

// next part BELOW ARE STANDART AND REUSED INSTANCE, DEVICE AND SWAPCHAIN , SO ITS JUST A COPY PASTE 
create_instance :: proc() -> vk.Instance {
	layers := []cstring{"VK_LAYER_KHRONOS_validation"}
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	extensions := make([dynamic]cstring)
	defer delete(extensions)
	append(&extensions, ..glfw_extensions)
	append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	append(&extensions, vk.EXT_DEBUG_REPORT_EXTENSION_NAME)

	app_info := vk.ApplicationInfo{
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Vulkan",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_1,
	}
	create_info := vk.InstanceCreateInfo{
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}
	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "creating instance")
	vk.load_proc_addresses(instance)
	return instance
}

find_suitable_physical_device :: proc(instance: vk.Instance, selector: proc(device: vk.PhysicalDevice) -> bool) -> (vk.PhysicalDevice, bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		return {}, false
	}
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	for device in devices {
		if selector(device) {
			return device, true
		}
	}
	return {}, false
}

find_queue_families :: proc(device: vk.PhysicalDevice, desired_flags: vk.QueueFlags) -> u32 {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))
	for family, i in families {
		if family.queueCount > 0 && (family.queueFlags & desired_flags == desired_flags) {
			return u32(i)
		}
	}
	return 0
}

create_device :: proc(physical_device: vk.PhysicalDevice, device_features: vk.PhysicalDeviceFeatures, graphics_family: u32) -> (vk.Device, vk.Result) {
	extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	queue_priority: f32 = 1.0
	queue_info := vk.DeviceQueueCreateInfo{
		sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = graphics_family,
		queueCount = 1, pQueuePriorities = &queue_priority,
	}
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

choose_swap_surface_format :: proc(available: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	return vk.SurfaceFormatKHR{format = .B8G8R8A8_UNORM, colorSpace = .SRGB_NONLINEAR}
}

choose_swap_present_mode :: proc(available: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	for mode in available {
		if mode == .MAILBOX {
			return mode
		}
	}
	return .FIFO
}

choose_swap_image_count :: proc(caps: vk.SurfaceCapabilitiesKHR) -> u32 {
	image_count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && image_count > caps.maxImageCount {
		return caps.maxImageCount
	}
	return image_count
}

create_swapchain :: proc(device: vk.Device, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR, graphics_family: u32, width, height: u32) -> (vk.SwapchainKHR, vk.Result) {
	caps: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &caps)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count)
	defer delete(formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, raw_data(formats))

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)
	present_modes := make([]vk.PresentModeKHR, present_mode_count)
	defer delete(present_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, raw_data(present_modes))

	surface_format := choose_swap_surface_format(formats)
	present_mode := choose_swap_present_mode(present_modes)
	family := graphics_family

	create_info := vk.SwapchainCreateInfoKHR{
		sType = .SWAPCHAIN_CREATE_INFO_KHR, surface = surface,
		minImageCount = choose_swap_image_count(caps),
		imageFormat = surface_format.format, imageColorSpace = surface_format.colorSpace,
		imageExtent = {width, height}, imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT, .TRANSFER_DST}, imageSharingMode = .EXCLUSIVE,
		queueFamilyIndexCount = 1, pQueueFamilyIndices = &family,
		preTransform = caps.currentTransform, compositeAlpha = {.OPAQUE},
		presentMode = present_mode, clipped = true, oldSwapchain = {},
	}
	swapchain: vk.SwapchainKHR
	result := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain)
	return swapchain, result
}

create_image_view :: proc(device: vk.Device, image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags) -> (vk.ImageView, bool) {
	view_info := vk.ImageViewCreateInfo{
		sType = .IMAGE_VIEW_CREATE_INFO, image = image, viewType = .D2, format = format,
		subresourceRange = {aspectMask = aspect_flags, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1},
	}
	view: vk.ImageView
	result := vk.CreateImageView(device, &view_info, nil, &view)
	return view, result == .SUCCESS
}

create_swapchain_images :: proc(device: vk.Device, swapchain: vk.SwapchainKHR) -> (images: []vk.Image, views: []vk.ImageView) {
	image_count: u32
	vk.GetSwapchainImagesKHR(device, swapchain, &image_count, nil)
	images = make([]vk.Image, image_count)
	views = make([]vk.ImageView, image_count)
	vk.GetSwapchainImagesKHR(device, swapchain, &image_count, raw_data(images))
	for i in 0 ..< image_count {
		view, ok := create_image_view(device, images[i], .B8G8R8A8_UNORM, {.COLOR})
		if !ok {
			fmt.println("failed to create image view for swapchain image", i)
			return
		}
		views[i] = view
	}
	return
}

// PART 3 - the init/destroy functions , this is the actual point of this recepie , everything from the last 2 parts is condensed into one function call , filling in one struct instead of a dozen seperate steps scatered through main()

init_vulkan_render_device :: proc( 
vk_instance : VulkanInstance , 
width , height : u32. 
selector: proc(device: vk.PhysicalDevice) -> bool,
device_features: vk.PhysicalDeviceFeatures,) -> (dev: VulkanRenderDevice, ok:bool) { 
physical_device , found := find_suitable_physical_device(vk_instance.instance , selector) 
if !found { 
 return {} , false 
} 
dev.physical_device = physical_device 
dev.graphics_family = find_queue_families(physical_device, {.GRAPHICS} ) 

device_result : vk.Result 
dev.evice , device_result = create_device9physical_device , device_features , dev.graphics_family) 
vk_check(device_result , " creating the device") 
vk.load_proc_addresses(dev.device) 

vk.GetDeviceQueue(dev.device , dev.graphics_family , 0 , &dev.graphics_queue) 
if dev.grapics_queue == nil { 
return dev , false 
} 

//double check this queue family can actually present  images to our specific window surface having a graphics queue doesnot sutomatically gurantee it can show things on screen 
present_supported: b32
	vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, dev.graphics_family, vk_instance.surface, &present_supported)
	if !present_supported {
		return dev, false
	}

	swapchain_result: vk.Result
	dev.swapchain, swapchain_result = create_swapchain(dev.device, physical_device, vk_instance.surface, dev.graphics_family, width, height)
	vk_check(swapchain_result, "creating swapchain")

	dev.swapchain_images, dev.swapchain_image_views = create_swapchain_images(dev.device, dev.swapchain)
	image_count := len(dev.swapchain_images)

	sem_result1: vk.Result
	dev.semaphore, sem_result1 = create_semaphore(dev.device)
	vk_check(sem_result1, "creating semaphore")

	sem_result2: vk.Result
	dev.render_semaphore, sem_result2 = create_semaphore(dev.device)
	vk_check(sem_result2, "creating render semaphore")

	pool_info := vk.CommandPoolCreateInfo{sType = .COMMAND_POOL_CREATE_INFO, queueFamilyIndex = dev.graphics_family}
	vk_check(vk.CreateCommandPool(dev.device, &pool_info, nil, &dev.command_pool), "creating command pool")

	dev.command_buffers = make([]vk.CommandBuffer, image_count)
	alloc_info := vk.CommandBufferAllocateInfo{
		sType = .COMMAND_BUFFER_ALLOCATE_INFO, commandPool = dev.command_pool,
		level = .PRIMARY, commandBufferCount = u32(image_count),
	}
	vk_check(vk.AllocateCommandBuffers(dev.device, &alloc_info, raw_data(dev.command_buffers)), "allocating command buffers")

	return dev, true
}

destroy_vulkan_render_device :: proc(dev: ^VulkanRenderDevice) {
	for view in dev.swapchain_image_views {
		vk.DestroyImageView(dev.device, view, nil)
	}
	delete(dev.swapchain_image_views)
	delete(dev.swapchain_images)
	delete(dev.command_buffers)

	vk.DestroySwapchainKHR(dev.device, dev.swapchain, nil)
	vk.DestroyCommandPool(dev.device, dev.command_pool, nil)
	vk.DestroySemaphore(dev.device, dev.semaphore, nil)
	vk.DestroySemaphore(dev.device, dev.render_semaphore, nil)
	vk.DestroyDevice(dev.device, nil)
}

destroy_vulkan_instance :: proc(vk_instance: ^VulkanInstance) {
	vk.DestroySurfaceKHR(vk_instance.instance, vk_instance.surface, nil)
	vk.DestroyDebugReportCallbackEXT(vk_instance.instance, vk_instance.report_callback, nil)
	vk.DestroyDebugUtilsMessengerEXT(vk_instance.instance, vk_instance.messenger, nil)
	vk.DestroyInstance(vk_instance.instance, nil)
}
