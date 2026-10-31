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

/* call once per main-loop iteration with the time since the previous one -
frame_rendered = false lets you skip counting an iteration where you chose not to draw. Returns true on the iterations where it printed. */

fps_counter_tick :: proc(counter : ^FramesPerSecondCounter , delta_seconds : f32 , frames_rendered := true) -> 
bool { if frame_rendererd{counter.num_frames += 1 } 
counter.accumulated_time += f64(delta_seconds) 
// not enough time yet: keep accumulating
if counter.accumulated_time < f64(counter.avg_interval_sec) {return false} 
// enough time - average, print, and start a new interval
counter.current_fps = f32(f64(counter.num_frames) / counter.accumulated_time) 
fmt.printf("FPS: %.1f\n", counter.current_fps)
counter.num_frames = 0
counter.accumulated_time = 0
return true
}

// read the last computed average without printing 
fps_counter_get :: proc(counter : FramesPerSecondCounter) -> f32 { 
return counter.current_fps
} 

/* main proc functions - 
