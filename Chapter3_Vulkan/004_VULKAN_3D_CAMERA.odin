// ADDITIONS ONLY - paste under your existing code in your combined file. No package line, nothing repeated.

/*  READ THIS FIRST: WHERE THE NEW CODE IS 
 [NEW-1] Camera & CameraPositionerInterface   The base API to work with the 3D camera. Uses a manual vtable (procedure pointers) to replicate C++ polymorphism
 [NEW-2] CameraPositioner_FirstPerson - The actual camera model. A quaternion-based first-person camera that can be freely moved in space[cite: 3].
 [NEW-3] MouseState & GLFW Callbacks - The demo application code to hook up GLFW input to the camera

 NEW ASSUMPTION (the only place this file differs from standard Odin)
  Odin's `core:math/linalg/glsl` is used as a direct 1:1 replacement for C++ `glm`. 
  Odin does not have classes or pure virtual methods, so `CameraPositionerInterface` stores a `data: rawptr` and 
  procedure variables to achieve the exact polymorphic behavior requested in the text[cite: 1, 2].
*/ 

 /* THE THINGS TO REMEMBER
 1. The interface of `CameraPositionerInterface` contains pure virtual methods in C++[cite: 2]. In Odin, we map this to a struct with explicit proc variables.
 2. The `update()` method should be called at every frame and take the time elapsed since the previous frame.
 3. Instead of controlling the camera speed or position directly, the user input controls only the acceleration vector directly, making behavior non-jerky
*/ 

import "core:math"
import "core:math/linalg/glsl"
import "vendor:glfw"

// [NEW-1] Camera & CameraPositionerInterface

//represents the pure virtual class CameraPositionInterface 
CamerPositionInterface :: struct { 
data : rawptr , 
get_view_matrix : proc(data : rawptr) -> glsl.mat4, 
get_position : proc(data : rawptr) -> glsl.vec3 , 
}

//represents the camera final class 
Camera :: struct { 
positioner : ^CameraPositionerInterface , 
} 

camera_get_view_matrix :: proc(c: ^Camera) -> glsl.mat4 { 
return c.positioner.get_view_matrix(c.positioner.data) 
}
camera_get_position :: proc(c: ^Camera) -> glsl.vec3 {
	return c.positioner.get_position(c.positioner.data)[cite: 2]
}

// [NEW-2] CameraPositioner_FirstPerson
// boolean flags that define the current motion of our camera 
Movement :: struct {
	forward:    bool,
	backward:   bool,
	left:       bool,
	right_:     bool,
	up_:        bool,
	down_:      bool,
	fast_speed: bool,
}

CameraPositioner_FirstPerson :: struct { 
interface : CameraPositionInterface , // polymorphic interface implementation 
movement : Movement , //decouples keyboard input from camera logic 
mouse_speed : f32 , 
acceleration : f32, 
damping : f32 , 
max_speed : f32 , 
fast_coef : f32 , // Parameters to tweak responsiveness and damping
mouse_pos : glsl.vec2, 
mouse_pos: glsl.vec2,
camera_position:glsl.vec3,
camera_orientation: glsl.quat,
move_speed: glsl.vec3,  // Private data members controlling state
}

// Non-default constructor taking initial position, target position, and up vector[cite: 5]
camera_positioner_first_person_init :: proc(self: ^CameraPositioner_FirstPerson, pos, target, up: glsl.vec3) {
self.mouse_speed  = 4.0
self.acceleration = 150.0
self.damping = 0.2
self.max_speed = 10.0
self.fast_coef = 10.0
self.mouse_pos = {0, 0}
self.camera_position = pos

// glm::lookAt constructs a matrix; we extract the quaternion from it for orientation[cite: 5]
look_at_mat  := glsl.mat4LookAt(pos, target, up)
self.camera_orientation = glsl.quat_from_matrix4(look_at_mat)
self.move_speed  = {0, 0, 0}

//populate the polymorphic vtable 
self.interface.data = self 
self.interface.get_view_matrix = proc(data : rawptr) -> glsl.mat4 { 
self := cast(^CameraPositioner_FirstPerson)data 
t := glsl.mat4Translate(self.camera_postition) 
r := glsl.mat4FromQuat(self.camera_orientation) 
return r*t 
} 

self.interface.get_position = proc(data: rawptr) -> glsl.vec3 {
self := cast(^CameraPositioner_FirstPerson)data
return self.camera_position
}
}

// Adds dynamics to the camera model
camera_positioner_update :: proc(self: ^CameraPositioner_FirstPerson, delta_seconds: f64, mouse_pos: glsl.vec2, mouse_pressed: bool) {
if mouse_pressed {
delta := mouse_pos - self.mouse_pos
delta_quat := glsl.quatEulerAngles(self.mouse_speed * delta.y, self.mouse_speed * delta.x, 0.0)
self.camera_orientation = glsl.normalize(delta_quat * self.camera_orientation)
}
self.mouse_pos = mouse_pos

// Extract forward, right, and up vectors from the 4x4 view matrix
v := glsl.mat4FromQuat(self.camera_orientation)
forward := -glsl.vec3{v[0][2], v[1][2], v[2][2]}
right_  :=  glsl.vec3{v[0][0], v[1][0], v[2][0]}
up := glsl.cross(right_, forward)

// Establish input state for camera acceleration
accel := glsl.vec3{0, 0, 0}
if self.movement.forward  do accel += forward
if self.movement.backward do accel -= forward
if self.movement.left     do accel -= right_
if self.movement.right_   do accel += right_
if self.movement.up_      do accel += up
if self.movement.down_    do accel -= up
if self.movement.fast_speed do accel *= self.fast_coef
dt := f32(delta_seconds)


// Decelerate if 0, otherwise integrate using Euler integration
if accel == {0, 0, 0} {
self.move_speed -= self.move_speed * math.min((1.0 / self.damping) * dt, 1.0)
} else {
self.move_speed += accel * self.acceleration * dt
max_speed := self.movement.fast_speed ? self.max_speed * self.fast_coef : self.max_speed
if glsl.length(self.move_speed) > max_speed {
self.move_speed = glsl.normalize(self.move_speed) * max_speed
}
}
self.camera_position += self.move_speed * dt
}

camera_positioner_set_position :: proc(self: ^CameraPositioner_FirstPerson, pos: glsl.vec3) {
	self.camera_position = pos
}

// Recalculates the camera orientation using the existing camera position and direction
camera_positioner_set_up_vector :: proc(self: ^CameraPositioner_FirstPerson, up: glsl.vec3) {
view := self.interface.get_view_matrix(self)
dir := -glsl.vec3{view[0][2], view[1][2], view[2][2]}
look_at_mat := glsl.mat4LookAt(self.camera_position, self.camera_position + dir, up)
self.camera_orientation = glsl.quat_from_matrix4(look_at_mat)
}

// Helper function to reset the previous mouse position to prevent jerky rotation
camera_positioner_reset_mouse_position :: proc(self: ^CameraPositioner_FirstPerson, p: glsl.vec2) {
self.mouse_pos = p
}

// [NEW-3] MouseState & GLFW Callbacks
MouseState :: struct {
pos: glsl.vec2,
pressed_left: bool,
}

// Global variables for the demo application
mouse_state: MouseState
positioner: CameraPositioner_FirstPerson
camera: Camera

// Call this once before your render loop
init_camera_globals :: proc() {
camera_positioner_first_person_init(&positioner, {0.0, 0.0, 0.0}, {0.0, 0.0, -1.0}, {0.0, 1.0, 0.0})
camera = Camera{positioner = &positioner.interface}
}

// GLFW cursor position callback updating normalized 0...1 coordinates
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
context = runtime.default_context()
width, height: i32
glfw.GetFramebufferSize(window, &width, &height)
mouse_state.pos.x = f32(x / f64(width))
mouse_state.pos.y = f32(y / f64(height))
}


// GLFW mouse button callback raises the pressedLeft flag
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
context = runtime.default_context()
if button == glfw.MOUSE_BUTTON_LEFT {
mouse_state.pressed_left = (action == glfw.PRESS)
}
}
