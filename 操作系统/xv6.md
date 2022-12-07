## traps
- gdbinit
```shell
layout asm
b *0x0000000000000dfe
c
b *$stvec
```
还有一个问题：进程切换时候寄存器的值是保存在trapframe中，那么此时进程中的其它变量保存在哪里呢？
- trap流程：ecall->uservec->usertrap->usertrapret->userret.
- 通过调试发现xv6通过ecall从用户态进入内核态的过程主要做了：
	1. 将user mode转换为supervisor mode。
	2. 在进入ecall的一瞬间令sepc=pc。
	3. 另pc=stvec来进入内核地址执行指令（stvec的值就是trampoline page的起始地址）。
	4. jump to pc（切换到了内核态）。
	5. 设置`scause`以反映产生陷阱的原因。
- 注意事项：
	1. 机器启动总是从内核开始运行的，机器启动时就在内核中，从内核空间到用户空间的唯一办法就是sret(supervisior mode return to user mode)指令。所以在任何用户代码执行ecall前，内核会设置好所有如SSCRATCH，STVEC的寄存器。
-  此时只是ecall（硬件上）帮忙做的，如果需要保存整个完整的状态机还需要手动写一些东西，即：
	- 我们需要保存32个用户寄存器的内容，这样当我们想要恢复用户代码执行时，我们才能恢复这些寄存器的内容。
	-   因为现在我们还在user page table，我们需要切换到kernel page table。
	-   我们需要创建或者找到一个kernel stack，并将Stack Pointer寄存器的内容指向那个kernel stack。这样才能给C代码提供栈。
	-   我们还需要跳转到内核中C代码的某些合理的位置。
- **uservec函数（位于Trampol.S中）**：通过ecall进入trampoline，保存程序寄存器至trapframe中（其中用到a0和sscratch互换以方便内核对用户页表做快照（因为sscratch对用户不可见）），然后跳转t0，即存放usertrap函数的地址对trap进行处理。
	- 注：uservec用来在用户态下处理trap，kernelvec用来在内核态下处理trap。
	- **问题1**：t0首先会读取trapframe中的kernel_trap，那么usertrap的地址是什么时候被保存到kernel_trap中的？
- **usertrap函数（位于trap.c中）**：首先将STVEC寄存器赋值为kernelvec的地址，将sepc寄存器的值存入trapframe的epc中（sepc之后可能被覆盖）然后判断scause寄存器的值是否为8，8表示陷入trap的原因是系统调用，如果是则打开中断执行syscall系统调用。syscall就根据系统调用号来执行对应的系统调用函数，寄存器a7保存系统调用号，a0,a1,a2分别保存write传入的三个参数文件描述符2，写入数据缓存的指针，写入数据的长度2。RISCV的abi中一般让a0存放函数调用返回值，于是syscall返回后回到trap.c中的usertrap函数。
- **usertrapret函数（trap.c中）**：usertrapret函数主要完成的是在返回到用户空间之前内核要做的工作。在进行将STVEC赋值为uservec前要进行关中断，不然后续中断来临时就会跳入user的中断处理程序，但此时我们仍是在内核态的。然后就是将STVEC寄存器储存trampoline代码，因为在那里储存着sret返回用户态的命令。然后就是将kernel page table，当前进程的内核栈，usertrap指针，cpu核编号储存到trapframe中，以便下一次（如问题1）从用户态进入内核态时候调用它们。然后就是修改用于控制sret，SPIE等符号位的SSTATUS寄存器。之后读取satp又是进入到trampo.S。
	- 问题2：第1次内核初始化是如何进行的？
- **userret函数**：该函数第一步是切换页表。在执行`csrw satp, a0`以前，页表还是巨大的kernel page table

### Page faults and cow(copy on write)
- sbrk：是xv6的系统调用，使得用户应用程序能扩大自己的heap。(注：heap的底端与stack位于相同的地址，只不过stack向下增长，heap向上增长)
- **lazy allocation**：相当于运行时动态分配堆内存。
- 想要理解**Copy On write fork**，首先要理解exec的执行过程。当shell执行一个指令的时候，首先会fork出一个当前shell的进程，然后再由该进程调用exec来运行其它程序（如echo）在普通情况下，fork会创建一份shell地址空间的完整拷贝，而exec做的第一件事情就是丢弃这个地址空间，取而代之的是一个包含了echo的地址空间。这样做就会造成资源的浪费。于是可以使fork出的子进程与父进程指向同一片物理地址，并将该地址中的PTE都设置为只读，于是当要向其中的某个物理地址写入时就会触发Page Fault，内核就可以拷贝一份该物理地址并与原物理地址都设置成可读可写，就可以实现父子进程的内存隔离。（注：还需要用RSW中的一位设置成copy-on-write page的标识位，以方便内核识别copy-on-write场景来进行具体的操作）
- **Demand Paging**：