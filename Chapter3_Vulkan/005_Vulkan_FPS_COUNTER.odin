//FRAMES PER SECOND COUNTER
// What it does: counts how many frames you draw, and every `avg_interval_sec` seconds divides frames by elapsed time to get an average FPS and prints it.

FramesPerSecondCounter :: struct { 
avg_interval_sec : f32, //how long to average over before printing 
num_frames : u32 , // frames drawn in the current interval 
accumulated_time : f64 , //secinds elasped in the current interval 
current_fps : f32 , //the last computed average 
} 

//default interval is 0.5 seconds and the interval must be positive 
fps_counter_init :: proc(avg_interval_sec: f32 = 0.5 ) -> FramesPerSecondCounter { 
assert(avg_internal_sec >0 ) 
return {avg_internal_sec = avg_interval_sec} 
} 

