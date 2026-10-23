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

