// A PROFILER WRAPPER YOU CAN SWITCH AT BUILD TIME
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
