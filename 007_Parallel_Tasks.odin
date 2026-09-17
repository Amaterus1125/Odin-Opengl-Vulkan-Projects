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
      thread.pool_init(&graph.pool , allocator = context.allocator, thread_count = thread_count) 
    // starting the pool here , not per frame , this is what makes this safe to reuse , the worker threads just sit ideal waiting on between frames , costing nothing but a few resident OS threads
     thread.pool_start(&graph.pool) 
} 

//SHUTDOWN - tears down worker threads , call this exactly once , when the engine subsystem that owns this graph is actually shutting down 
destroy_task_graph :: proc(graph: ^Task_Graph) {
     //finishes any in flight taks , then joins and stps every worker thread , after this the pool cannot be restarted and that's fine since we only call this at real shutdown
thread.pool_join(&graph.pool)
thread.pool_destroy(&graph.pool)
delete(graph.jobs)
}

//per frame job runningby reusing the already running pool instead of rebuilding anything 
run_frame :: proc(graph : ^Task_Graph , items: []int) {
   //the start task , since nothing here depends on anything except "did s run yet" , running it synchronously right here already satisfies its one dependency rule , it happens before evry task is queded
  fmt.println("\nS- Start")
//grow the scratch buffer only if this frame needs more slots than we have ever needed before 
if len(graph.jobs) < len(items) {
  resize(&graph.jobs , len(items))
}

//arm the counter with exactly how many item tasks we are about to hand out this frame 
sync.wait_group_add(&graph.wg , len(items))

// NOTE -  `&items[i]` and `&graph.wg` only need to stay valid until wait_group_wait() returns below - both do, since `items` is the caller's slice for this frame and `graph` outlives the call.
for i in 0 ..<len(items) { 
    graph.jobs[i] = Item_Job{value = &items[i] , wg = &graph.wg}
    thread.pool_add_task(
         &graph.pool,
         allocator = context.allocator ,
         procedure = print_item_task,
         data = &graph.jobs[i] ,
         user_index = i ,
) }
// Block until every item task for THIS frame has called
sync.wait_group_wait(&graph.wg) 

// The pool keeps finished tasks around until you pop them; drain them now so the pool's internal "done" list doesn't grow forever across thousands of frames.
for { 
      _, got_task := thread.pool_pop_done(&graph.pool)
         if !got_task {
             break
           }
}
}
// Writing a graphviz.dot file describing the fixed fixed S -> items -> T shape
//The graph's SHAPE doesn't change frame to frame (only the item values do), so this only needs to run once, not every frame.

write_dot_graph :: proc(item_count : int) { 
  handle , err := os.open("taskflow.dot" , os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
  if err != nil { 
       fmt.eprintln("could not write taskflow.dot:" , err)
       return 
} 
defer os.close(handle)
fmt.fprintln(handle, "digraph Taskflow {")
for i in 0 ..< item_count{
       fmt.fprintfln(handle, "\tS -> item_%d;", i)
		fmt.fprintfln(handle, "\titem_%d -> T;", i)
	}
fmt.fprintln(handle, "}")
}

main :: proc() { 
   // by default; core:sys/info's cpu_core_count() is the Odin equivalent, returning both physical and logical (hyperthreaded) core counts.
thread_count := 4 //fallback if the core count can't be queried 
if _, logical , ok := info.cpu_core_count(); ok {
       thread_count = logical }

graph : Task_Graph 
init_task_graph(&graph , thread_count) //once at startup 
defer destroy_task_graph(&graph)    //once at shutdown 

write_dot_graph(8) // graph shape is fixed , so this only needs to run once too 
items := [8]int{1,2,3,4,5,6,7,8}


	// Stand-in for a game loop: the SAME graph (same pool, same worker threads, same Wait_Group) gets reused every "frame" - only the data changes. This is the part a naive one-shot translation would mind , and the part that actually matters for engine performance.
	for frame in 0 ..< 3 {
		fmt.printfln("=== frame %d ===", frame)
		run_frame(&graph, items[:])
	}
}
