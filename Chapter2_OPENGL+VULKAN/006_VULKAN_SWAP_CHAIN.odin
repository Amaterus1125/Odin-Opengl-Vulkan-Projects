// the basic package imports and the check for if vulkan call failed or not , very imp 
package main

import "core:fmt"

import "vendor:glfw"
import vk "vendor:vulkan"

vk_check :: proc(result: vk.Result, what: string) {
	if result != .SUCCESS {
		fmt.println("VULKAN ERROR during", what, "-", result)
		panic("vulkan call failed")
	}
}


// PART 1 - INSTANCE  DEVICE (same as previous recipe and file , you can just copy the 005 file here
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


find_suitable_physical_device :: proc(
	instance: vk.Instance,
	selector: proc(device: vk.PhysicalDevice) -> bool,
) -> (vk.PhysicalDevice, bool) {
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

create_device :: proc(
physical_device: vk.PhysicalDevice,
device_features: vk.PhysicalDeviceFeatures,
graphics_family: u32,
) -> (vk.Device, vk.Result) {
extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
queue_priority: f32 = 1.0
queue_info := vk.DeviceQueueCreateInfo{
sType  = .DEVICE_QUEUE_CREATE_INFO,
queueFamilyIndex = graphics_family,
queueCount = 1,
pQueuePriorities = &queue_priority,
	}
features_local := device_features
create_info := vk.DeviceCreateInfo{
sType  = .DEVICE_CREATE_INFO,
queueCreateInfoCount  = 1,
pQueueCreateInfos  = &queue_info,
enabledExtensionCount = u32(len(extensions)),
ppEnabledExtensionNames = raw_data(extensions),
pEnabledFeatures = &features_local,
}
device: vk.Device
result := vk.CreateDevice(physical_device, &create_info, nil, &device)
return device, result
}

//PART 2 - THE SWAP CHAIN ITSELF - a swap chain is a small queue of images that get rendered into offscreen , one at a time , then shown on screen when ready, vulkan does not have a single swap buffers function like opengl does , so we have to explicitly ask for and manage these images ourselves 

SwapchainSupportDetails :: struct { 
capabilities : vk.SurfaceCapabilitiesKHR . 
formats : []vk.SurfaceFormatKHR , 
present_modes : []vk.PresentModelKHR, 
} 
// ask the gpu + surface combo - what are u actually capable of here , different gpu/drivers/operating systems support different image formats and presentaion styles , so we have to check rather than asume
query_swapchain_support :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> SwapchainSupportDetails {
details: SwapchainSupportDetails
vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities)

format_count: u32
vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil)
if format_count > 0 {
details.formats = make([]vk.SurfaceFormatKHR, format_count)
vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, raw_data(details.formats))
}
present_mode_count: u32
vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, nil)
if present_mode_count > 0 {
details.present_modes = make([]vk.PresentModeKHR, present_mode_count)
vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, raw_data(details.present_modes))
}
return details
}

//which image format to actually use , we are just hardcoding a common, widely supported choice ( 8 bit per color channel, standart sRGB color space) rather than just picking dynamically from what's available 
choose_swap_surface_format :: proc(available: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR{ 
 return vk.SurfaceFormatKHR{ format = .B8G8R8A8_UNORM, colorSpace = .SRGB_NONLINEAR}
}

/* "present mode" = the algoritm for when a newly finished frame actually gets shown, MAILBOX is the nice one, it shows the newest frame the moment it's ready, no visible tearing and does not 
force our game to wait around, not every system supports it through, so we fall back to FIFO (regular vsync) */
choose_swap_present_mode :: proc(available : []vk.PresentModeKHR) -> vk.PresentModeKHR {
 for mode in available 
 if mode == .MAILBOX { 
 return mode 
} 
} 
 return .FIFO //every vulkan driver is required to support this ome so it is a safe fallback if MAILBOX does not work 
} 

// so how many images should the swap chain actually hold? using just the gpu bare minimum can mean the gpu sometimes has to sit and wait for image to free up, requesting one extra will avoid this stalling, capped at whatever the gpu actual maximum allows
choose_swap_image_count :: proc(caps: vk.SurfaceCapabilitiesKHR) -> u32 { 
 image_count := caps.minImageCount + 1 
if caps.maxImageCount > 0 && image_count > caps.maxImageCount {
 return caps.maxImageCount 
} 
return image_count 
} 

create_swapchain :: proc{ 
 device: vk.Device,
physical_device : vk.PhysicalDevice,
surface : vk.SurfaceKHR,
graphics_family : u32,
width , height : u32,
} -> (vk.SwapchainKHR, vk.Result) {
support := query_swapchain_support(physical_device , surface) 
defer delete(support.formats)
defer delete(support.present_modes)
surface_format := choose_swap_surface_format(support.formats)
present_mode := choose_swap_present_mode(support.present_modes) 
family := graphics_family 

create_info := vk.SwapchainCreateInfoKHR{
sType = .SWAPCHAIN_CREATE_INFO_KHR,
surface = surface , 
minImageCount = choose_swap_image_count(support.capabilities),
