// A PROFILER WRAPPER YOU CAN SWITCH AT BUILD TIME and profielrs are used for optimisation purposes , basically u can tell what block of code is causing you CPU or GPU bottlenecks and you can fix them later 
/* Needs at the top of the file:
import "core:fmt"
import "core:slice"
import "core:sync"
import "core:time"
import "core:prof/spall" */

/* THE IDEA FROM THE BOOK: write your profiling calls ONCE, using one small set of names, and choose at build time which profiler (or none) they really call. 
WHAT Happens IN ODIN -
EasyProfiler and Optick are C++ libraries and Odin has no bindings for them, so this wraps what Odin DOES have instead:
"none" - profiling calls compile to nothing (zero cost)
"console" - a tiny built-in timer that prints a table at the end (plays the role of EasyProfiler's block statistics)
"spall"   - Odin's built-in core:prof/spall, which writes a file you open in the Spall viewer (plays the role of Optick's saved capture + flamegraph)
"tracy"   - the Tracy profiler, through the community odin-tracy bindings (the production choice: live flamegraph, GPU and memory profiling). Needs extra setup, see Part 5.
And the C++ / CMake machinery maps like this:
CMake option(...) + add_definitions ->  #config + -define:PROFILER=...
#if BUILD_WITH_...   ->  `when PROFILER == "..."`
#error "cannot enable both"  ->  #assert (only ONE value can be picked)
empty macros when disabled  ->  @(disabled = ...) on the procs
OptickScopeWrapper (RAII class)  ->  @(deferred_in = ...)  
 
CHOOSE THE PROFILER WHEN YOU BUILD (the default is "none"):
odin run 16.odin -file // no profiling
odin run 16.odin -file -define:PROFILER=console
odin run 16.odin -file -define:PROFILER=spall
odin run 16.odin -file -define:PROFILER=tracy -define:TRACY_ENABLE=true -debug -o:speed (tracy only: see Part 5 first) */

// PART 1: THE BUILD OPTION
PROFILER :: #config(PROFILER, "none") 

//errors out if both profilers are on; here a single string means that can't happen, so we only reject unknown values
#assert(PROFILER == "none" || PROFILER == "console" || PROFILER == "spall" || PROFILER == "tracy", "PROFILER must be none, console, spall or tracy")

// colors for blocks. Same idea as the book's profiler::colors constants: callers use one set of names, whatever the backend does with them. (Neither built-in backend draws colors; the argument is kept so your calls stay identical if you later plug in a profiler that does.)
Profiler_Color :: enum u32 { 
Magenta = 0xFF00FF,
Green   = 0x00FF00,
Red     = 0xFF0000,
}

// PART 2 - Backend state , only the chosen backend data exist 
//keep every impord used even for the backends not selected (otherwise building with -vet complains about unused imports ) 
_fmt_anchor :: fmt.info 
_slice_anchor :: slice.sort_by 
_sync_anchor :: sync.current_thread_id 
_time_anchor:: time.Tick 
_spall_anchor :: spall.BUFFER_DEFAULT_SIZE

when PROFILER == "console" { 
// a block that has started but not ended yet 
@(private = "file") Open_Block :: struct { 
name : string , 
start : time.Tick , 
} 
// totals for the every block with same name 
@(private = "file") Block_Stat :: struct { 
total : time.Duration 
max: time.Duration , 
count : int , 
} 
@(private = "file") open_blocks: [dynamic]Open_Block // acts as a stack, so blocks can nest
@(private = "file") block_stats: map[string]Block_Stat
@(private = "file") frame_count: int
}

when PROFILER == "tracy" { 
	// Tracy's begin gives back a "zone" handle that the matching end needs,so we keep open zones on a stack (blocks nest, so last begun = first ended)
#assert(tracy.TRACY_ENABLE, "PROFILER = tracy also needs -define:TRACY_ENABLR= true , otherwise tracy records nothing") 
@(private = "file") tracy_zones : [dynamic]tracy.ZoneCtx
} 

when PROFILER == "spall" { 
@(private = "file") spall_ctx : spall.Context 
@(private = "file" ) spall_backing :[]u8   //memory the events are buffered in before writing 
@(private = "file") @(thread_local) spall_buffer: spall.Buffer
}

// PART 3 - API calling , those are calls we put in the program 
//every proc below is marked with "disabled" when PROFILER is "none" , the compiler removes the calls completly 

// EASY_PROFILER_ENABLE - calls once per startup 
@(disable = PROFILER == "none") 
profiler_enable :: proc(file_name := "profile.spall") { 
when PROFILER == "console" { 
reserve(&opem_blocks, 64) } 
else wjen PROFILER == "tracy" {
reserve(&tracy_zones , 64) } 
else when PROFILER == "spall" { 
// spall streams events into a file, so the file is opened now (PROFILER_DUMP later just flushes and closes it)
spall_ctx = spall.context_create(file_name)
spall_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
spall_buffer = spall.buffer_create(spall_backing, u32(sync.current_thread_id()))
}}

// EASY_MAIN_THREAD / EASY_THREAD_SCOPE - give the current thread a name
@(disable = PROFILER == "none" ) 
profiler_thread :: proc(name : cstring , loc := #caller_location) { 
when PROFILER == "tracy" { 
tracy.SetThreadName(name) 
} else when PROFILER == "spall" { 
spall.buffer_name_thread(&spall_ctx , &spall_buffer , string(name) , loc) 
}}

// EASY_BLOCK(name, color): start a named block. Pair with profile_block_end(). Blocks can nest; each end closes the most recently started block.

@(disabled = PROFILER == "none")
profile_block_begin :: proc(name: string, color: Profiler_Color = .Green, loc := #caller_location) {
when PROFILER == "console" {
append(&open_blocks, Open_Block{name, time.tick_now()})
} else when PROFILER == "tracy" {
// the Profiler_Color value is 0xRRGGBB, which is what Tracy expects
append(&tracy_zones, tracy.ZoneBegin(true, tracy.TRACY_CALLSTACK, name, u32(color), loc))
} else when PROFILER == "spall" {
spall._buffer_begin(&spall_ctx, &spall_buffer, name, "", loc)
}
}

// EASY_END_BLOCK - 
@(disable = PROFILER == "none") 
profiler_block_end :: proc() { 
when PROFILER == "console" {
block := pop(&open_blocks) 
elasped := time.tick_diff(block.start , time.tick_now()) 
stat := block_stats[block.name] //zeroed if this is the first time 
stat.total += elasped 
stat.max = max(stat.max , elasped) 
stat.count += 1 
block_stats[block.name] = stat } 
else when PROFILER == "tracy" {
tracy.ZoneEnd(pop(&stracy_zones) ) 
} else when PROFILER == "spall" { 
spall._buffer_end(&spall_ctx , &spall_buffer) 
} 
} 

// the SCOPED form. The book's EasyProfiler blocks close themselves when the scope ends (C++ RAII); Optick needed a wrapper class for that. In Odin,`deferred_in` does it - calling profile_scope("x") runs the matching "end" proc automatically when the surrounding scope exits. 
@(disabled = PROFILER == "none")
@(deferred_in = profile_scope_end)
profile_scope :: proc(name: string, color: Profiler_Color = .Green, loc := #caller_location) {
profile_block_begin(name, color, loc)
}














