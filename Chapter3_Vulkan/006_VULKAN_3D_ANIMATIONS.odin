// ADDITIONS ONLY - CAMERA ANIMATION: THE "MOVE TO" CAMERA + A CAMERA PICKER UI

/* Needs at the top of your file: the libraries I picked 
import "core:fmt"
import "core:math"
import "core:math/linalg"
import mu "vendor:microui"  */

/* THE IDEAis that a "positioner" is anything that can answer "where is the camera and what is its view matrix?". We already have the first-person one (free fly with keyboard/mouse). Here we add a second one, MoveTo, which
glides the camera smoothly to a position and rotation you type in with sliders. A combo box picks which positioner the camera listens to. */

// PART 1 - THE MOVE TO CAMERA POSITIONER
/* it keeps 2 copies of position and angles: where the camera IS (current) and where you WANT it (desired). Every frame, current moves a fraction of
the way toward desired. Moving a fraction of the REMAINING distance means it starts fast and slows down as it arrives a smooth glide, no extra animation code needed. */

CameraPositionerMoveTo :: struct { 
damping_linear:f32,    // for position
damping_euler_angles: [3]f32, // for pitch, pan, roll
position_current: [3]f32,
position_desired: [3]f32,
angles_current: [3]f32, // pitch, pan, roll in DEGREES
angles_desired: [3]f32,
current_transform: matrix[4, 4]f32, // the view matrix, rebuilt every frame
}

// the constructor starts current and desired at the same spot, so the camera doesn't move until you change the desired values

move_to_init :: proc(pos , angles : [3]f32) -> CameraPositionMoveTo { 
return { 
damping_linear = 10.0 , 
damping_euler_angles = { 5,5,5} 
