package main 

// Parallel tasks - in odin (my first time doing it) 
/* Normal Parellelism - spawn one os thread per job , do the work and then join , fine for 4 jobs but fails apart once a renderer has 
hundreds of small jobs per frame (like mesh culling) , so making multiple os threads and then destroying them is expensive.

 ODIN core:thread.Pool - so instead of pool tracking " wait for these N taks" internally like Taskflow in CPP , we use core:sync.Wait_Group as an external "how many item tasks are 
 still outstanding this frame" counter.
 Each item task decrements it when done, run_frame() blocks on it instead of tearingg the pool down, this makes the pool safely 
 reusable frame after frame at the cosr of only re-arming a counter , no thread creation , no allocation in the steady state. */
