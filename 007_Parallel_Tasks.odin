package main 

// Parallel tasks - in odin (my first time doing it) 
/* Normal Parellelism - spawn one os thread per job , do the work and then join , fine for 4 jobs but fails apart once a renderer has 
hundreds of small jobs per frame (like mesh culling) , so making multiple os threads and then destroying them is expensive.

 ODIN core:thread.Pool - so instead of pool tracking " wait for these N taks" internally like Taskflow in CPP , we use core:sync.Wait_Group as an external "how many item tasks are 
 still outstanding this frame" counter.
 Each item task decrements it when done, run_frame() blocks on it instead of tearingg the pool down, this makes the pool safely 
 reusable frame after frame at the cosr of only re-arming a counter , no thread creation , no allocation in the steady state. */

import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:sys/info"

/* everything one item taks needs , bundled into one struct so a single rawptr (task.data) can carry both peices of information across the thread-pool boundry */

Item_Job :: struct { 
    value : ^int,                //which array slot this task processes 
    wg: ^sync.Wait_Group,        // decremented when task is donw 
}

//The persistent , engine owned state , build this once , keep it alive for the life of the program ( or level or subsystem) ,hand a pointer to it into yr dreame loop 
Task_Graph :: struct { 
    pool: thread.Pool,
    wg: sync.Wait_Group,
 //resued scratch buffer for this frame job, grows on first use and only grows agaian if a future frame needs more items than any of the frame before it , after that its zero extra allocations per frame 
   jobs: [dynamic]Item_Job,
}

// the "item" task itself , the odin stand-in feature runs on whichever worker thread it picks up 
print_item_task :: proc(task: thread.Task) {
   job := (^Item_Job)(task.data)

// os.current_thread_id() -- which OS thread printed this , the actual source of the nondeterministic ordering in the output 
fmt.printfln("%v runs %v" , os.current_thread_id() , job.value^)
//tell run_frame() this one item is done ,once every item task has called this , the Wait_Group counter hits zero and run_frame() 's wait block below unblocks
sync.wait_group_done(job.wg) 
}

// THE STARTUP - constructing the graph once 
init_task_graph :: proc(graph: ^Task_Graph, thread_count:int) { 
      thread.pool_init(&graph.pool , allocator = context.allocator, thread_count - thread_count) 
    // starting the pool here , not per frame , this is what makes this safe to reuse , the worker threads just sit ideal waiting on between frames , costing nothing but a few resident OS threads
     thread.pool_start(&graph.pool) 
} 

//SHUTDOWN - tears down worker threads , call this exactly once , when the engine subsystem that owns this graph is actually shutting down 
