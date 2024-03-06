- **JIT**：JIT分为Method-Based JIT，Trace-Based JIT和Region-Based JIT。(Method是实例化的对象中的函数，function是类中定义的函数)
1. **Method-Based JIT**：其中关键的数据结构是vtable。**vtable**是一张用于存放多个虚函数的表，其是一个指针数组，存储了虚拟方法的地址。调用函数的时候可以通过对vtable进行地址偏移来选取对应的函数。每次调用method就可以快速的根据vtable来调用。注：Method-Based JIT默认编译所有冷热代码。
	pseudocode如下：
```c++
vtable = *ovar;// Get vtable pointer from ovar pointer
foo_funcptr = *(vtable + foo_offset); //get pointer to foo()
(*foo_funcptr)(); //invoke foo()
```
如果方法未经JIT compiler编译需要跳入trampoline进行编译。首先将method数据结构简化版的trampoline如下：
```c++
pushl $0x7001234 //address of foo()’s description
call $0x7005678 //address of jit_compile(method)
jmp %eax //eax holds the compiled code entry address
```
trampoline首先将virtual method（即实例化的对象中的虚函数）`foo()`的数据结构（即包含各种传入参数）的地址压入栈中，此时runtime stack就有了传入参数以及返回地址ra，有了这些参数通过调用`jit_compile()`来将方法编译为machine code，下一次调用该方法时候便可以直接调用编译过的machine code（相当于一条super instruction）来加速执行。
2. **Trace-Based JIT**：为了减少编译时间和空间浪费，Traced-Based JIT只根据运行时热度编译特定路径上的代码。Trace-Based JIT主要有三个任务：1. 确定trace。2. 编译并缓存trace路径上的代码。 3. 自适应管理trace。为了分析代码热度一般在潜在的trace入口插入计数器进行计数，当计数器达到一个阈值时便可认为该trace为热路径。通常有三个地方可以作为潜在的trace入口用于插入计数器：一个method prolog（方法前序）；循环头；basic block（基本块）（具体如何描述？）
		dalvik VM就在基本块（basic block）层面对代码进行热度分析。其在每一个单独最大的基本块中插入计数器。这里的基本块是一个编译器术语，指的是具有单个入口点和出口点的代码段。最大基本块即再插入任何指令其就不能成为一个基本块。
	对于basic-block-based tracing，基本块可以被chained来避免涉及运行时服务和解释器。链接的过程就是当知道一个trace退出后会进入另一个trace，那么控制流就可以直接转换到下一个trace。链接的trace可以形成一个trace树或trace图。
	loop-based traceing有一个好处就是只要方法在循环跟踪的路径中，其就可以自动内联方法。而basic-block-based tracing通常不会贯穿整个方法（除非该方法十分简单只需要一次跳转）
3. **Region-Based JIT**：Region-based JIT可以被认为是method-based JIT和trace-based JIT的混合体。类似于更小细粒度的method-based JIT。有时编译整个方法会造成不必要的开销，该JIT便可以选择性的编译代码的特定区域，这些区域通常是在程序运行时经常执行的热点代码路径。
		对于类似Java的静态类型语言，region-based JIT可以通过禁止编译整个method的方式来使其能在内存受限的平台上良好的工作。对于动态类型语言，region-based JIT可以使用类型专用化来避免跟踪扩展（trace explosion）dalvik VM在一定程度上就可以认为是region-based JIT。