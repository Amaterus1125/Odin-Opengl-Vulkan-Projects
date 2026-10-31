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
damping_euler_angles = { 5,5,5} ,
position_current  = pos,
position_desired = pos,
angles_current = angles,
angles_desired = angles,
current_transform = 1, // identity matrix
}
}

//called by the UI sliders 
move_to_set_desired_position :: proc(p: ^CameraPositionerMoveTo, pos: [3]f32) { p.position_desired = pos }
move_to_set_desired_angles :: proc(p: ^CameraPositionerMoveTo, angles: [3]f32) { p.angles_desired = angles }

move_to_view_matrix :: proc(p: CameraPositionerMoveTo) -> matrix[4, 4]f32 { return p.current_transform }
move_to_position :: proc(p: CameraPositionerMoveTo) -> [3]f32 { return p.position_current }

// now helpers for angles 

//wraps an angle that jumped past + or - 180 back around , so the camera always turns the short way 
clip_angle :: proc(d: f32) -> f32 { 
if d < -180 { return d + 360}
if d < 180 { return d - 360}
return d 
}

// keeps each angle inside one full turn 
clip_angles :: proc(angles: [3]f32) -> [3]f32 {
return {math.mod(angles.x, 360), math.mod(angles.y, 360), math.mod(angles.z, 360)}
}

//the shortest signed difference between 2 sets of angles 

angle_delta :: proc(angles_current , angles_desired : [3]f32 ) -> [3]f32 {
d := clip_angles(angles_current) - clip_angles(angles_desired) 
return { clip_angle(d.x) , clip_angle(d.y) , clip_angle(d.z) } 
} 


//the per-frame update - this is where the motion happens (mouse_pos and mouse_pressed are unused; the signature matches the other positioners so they're interchangeable)

move_to_update :: proc(p: ^CameraPositionerMoveTo , delta_seconds : f32 , mouse_pos : [2]f32 , mouse_pressed : bool) { 

//  1. position: step toward the desired position. The step is proportional to the remaining distance, scaled by damping and by the frame time (so it looks the same at any frame rate)
p.position_current += p.damping_linear * delta_seconds * (p.position_desired - p.position_current) 

// 2. angles: keep both sets in range first
p.angles_current = clip_angles(p.angles_current)
p.angles_desired = clip_angles(p.angles_desired)

// 3. same idea for the angles, using the SHORTEST difference
p.angles_current -= delta_seconds * angle_delta(p.angles_current, p.angles_desired) * p.damping_euler_angles
p.angles_current = clip_angles(p.angles_current)

/* 4. build the view matrix: degrees -> radians, rotate, then move the world opposite to the camera position. Note the swizzle: the angles
are stored as (pitch, pan, roll) = (x, y, z) but yaw-pitch-roll wants (yaw = pan = y, pitch = x, roll = z). That rotation is Ry * Rx * Rz. */ 
ang := p.angles_current * (math.PI / 180)
rotation := linalg.matrix4_rotate_f32(ang.y, {0, 1, 0}) * linalg.matrix4_rotate_f32(ang.x, {1, 0, 0}) * linalg.matrix4_rotate_f32(ang.z, {0, 0, 1})
p.current_transform = rotation * linalg.matrix4_translate_f32(-p.position_current)
}

// PART 2: SETUP AND THE PER-FRAME UPDATE
// the two camera types the combo box chooses between
CameraType :: enum {
First_Person,
Move_To,
}

// globals 
camera_pos:[3]f32 = {0, 0, 0}
camera_angles: [3]f32 = {-45, 0, 0}

positioner_first_person: CameraPositionerFirstPerson
positioner_move_to: CameraPositionerMoveTo
camera_type: CameraType = .First_Person

// call once at startup
init_cameras :: proc() {
positioner_first_person = first_person_init(camera_pos, {0, 0, -1}, {0, 1, 0})
positioner_move_to = move_to_init(camera_pos, camera_angles)
reinit_camera()
}

// call every frame from the main loop: update BOTH positioners, so whichever one the camera isn't using keeps tracking and won't jump when you switch
update_cameras :: proc(delta_seconds: f32) {
first_person_update(&positioner_first_person, delta_seconds, mouse_state.pos, mouse_state.pressed_left)
move_to_update(&positioner_move_to, delta_seconds, mouse_state.pos, mouse_state.pressed_left)
}

/* points the camera at the positioner chosen by camera_type. How you do this depends on how your Camera was written earlier, e.g.:
switch camera_type {
case .First_Person: camera = make_camera(&positioner_first_person)
case .Move_To:      camera = make_camera(&positioner_move_to)
} */ 
reinit_camera :: proc() {
// some code here 
} 

// PART 3: THE CAMERA PICKER UI, WITH MICROUI

