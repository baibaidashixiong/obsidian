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


### Multithreading
- 线程的状态包括三部分：
	1. 程序计数器PC。
	2. 保存变量的寄存器callee register。
	3. 程序的Stack。通常来说每个线程都有属于自己的Stack，Stack记录了函数调用的记录，并反映了当前线程的执行点。
- 线程的特点：线程会运行在所有可用的CPU核上，每个CPU核会在多个线程之间切换。
	- 不同线程系统之间的一个主要区别就是线程之间是否会共享内存。
		1. 如果多个线程共享一个地址空间，那么其中一个线程修改了一个变量，共享地址空间中的其它线程可以看到变量的修改。所以当多个线程运行在一个共享地址空间时，就需要用到锁。XV6内核共享了内存，并且XV6支持内核线程的概念，对于每个用户进程都有一个内核线程来执行来自用户进程的系统调用。所有的内核线程都共享了内核内存。
		2. XV6还有另外一种线程，每一个用户进程都有独立的内存地址空间，并且包含了一个线程，这个线程控制了用户进程代码指令的执行。
- XV6中采用用户进程和内核线程一一对应的的多线程模型（multithreading model），其进程切换过程为：
	1. 从第一个用户进程进入到内核中，保存用户**进程**的状态并运行第一个用户的内核**线程**。
	2. 在内核中从第一个用户进程的**内核线程**通过线程调度器scheduler切换到第二个用户进程的内核线程。
	3. 第二个用户进程的内核线程暂停自己，并恢复第二个用户进程的用户寄存器。
	4. 最后返回第二个用户进程继续执行。
- XV6进程切换过程：P1->usertrap->yield->sched->swtch->
- XV6中从一个正在运行的用户空间进程切换到另一个RUNABLE但是还没有运行的用户空间进程的更完整的过程是：首先假设进程P1正在运行，进程P2是RUNABLE当前并不在运行。假设XV6中有两个核CPU0核CPU1：
	1. 首先一个定时器中断强迫CPU从用户空间进程切换到内核（yield函数），trampoline代码将用户寄存器保存用于用户进程对应的trapframe对象中；
	2. 之后在内核中运行usertrap来实际执行相应的中断处理程序。此时CPU正在进程P1的内核线程和内核栈上执行内核中普通的C代码；
	3. 假设进程P1对应的内核线程决定让其让出CPU，则其最后会调用`swtch`函数。（XV6中一个CPU上运行的内核线程可以直接切换到的是这个CPU对应的调度器线程）
	4. swtch函数会保存用户进程P1对应内核线程的寄存器至context对象。目前为止的两类寄存器：用户寄存器保存在trapframe中，内核线程的寄存器存在context中。
- 由于CPU上运行的内核线程可以直接切换的是CPU对应的调度器线程，所以当P1运行swtch后（假设运行在CPU0），swtch函数会恢复之前为CPU0的调度器线程保存的寄存器和stack pointer，之后就在调度器线程的context下执行schedulder函数。
	- 调度器线程的工作过程：
	1. 将进程 P1设置成RUNABLE状态，再通过进程表单找到下一个RUNABLE进程（如P2），然后schedulder函数会再次调用swtch函数。
	2. 先保存自己的寄存器到调度器线程的context对象。
	3. 找到进程P2之前保存的context，恢复其中的寄存器。
	4.  由于P2在进入RUNABLE状态前也必定调用了swtch函数，所以之前的swtch函数会被恢复，并返回到进程P2所在的系统调用或者中断处理程序中（注：因为P2进程之前调用swtch函数必然在系统调用或者中断处理程序中）
	5. 当内核线程执行完成以后，trapframe中的用户寄存器会被恢复，返回到用户态执行用户进程P2.
（注：每个CPU都有一个完全不同的调度器线程，调度器线程也是一种内核线程，它也有自己的context对象。任何运行在CPU1上的进程，当其决定让出CPU都会切换到C PU1对应的调度器线程，并由调度器线程切换到下一个进程）

### Networking
[E1000网卡手册]([8254x Family of Gigabit Ethernet Controllers Software Developer’s Manual (mit.edu)](https://pdos.csail.mit.edu/6.828/2022/readings/8254x_GBe_SDM.pdf))，接收描述符和发送描述符的细节都在第三章。
- **接收描述符**：
实验中模拟的网卡是E1000，`e1000_init()`函数可以配置E1000使其可以从内存中直接读取数据包，也可以直接将数据包写入到RAM中，而不用经过CPU处理，触发中断等操作，即DMA技术。由于E1000处理数据包的速度跟不上收发网络包的速度，于是在`e1000_init()`中提供了多个buffer来供E1000写数据包。这些存放在RAM中的buffer数组被称为`descriptors`，每一个`descriptor`都包含着一个可供E1000写网络包的内存地址，结构体`rx_desc`中定义了`descriptor`的格式。`descriptors`组成的数组一般被称为接收环(receive ring)或接收队列。
```c
struct rx_desc
{
  uint64 addr;       /*  descriptor的地址 */
  uint16 length;     /* 写入addr的数据包长度 */
  uint16 csum;       /* Packet checksum */
  uint8 status;      /* Descriptor status */
  uint8 errors;      /* Descriptor Errors */
  uint16 special;
};
```
描述符格式：
![[networking描述符.png]]

- **环形队列**：
如果网卡收到了新的数据，会往环形队列 `head` 位置描述符的缓冲区写入数据，下图展示了接收描述符环形队列的结构：
![[networking环形队列.png]]
初始化时，`head` 为 0，`tail` 为队列缓冲区减一。
其中，`head` 到 `tail` 的这段浅色的区域是空闲的（图有点问题，其实 `tail` 指向的位置也时空闲的）。也就是说，这个区域内的数据包都已经被软件处理好了，那么如果有新的数据包到达，网卡会把数据写入这个区域的开始，也就是 `head`，把老的数据覆盖掉。网卡把老的数据覆盖掉后会把 `head` 的值加一。
而软件会按照顺序处理深色的区域。读取环形队列时，读取的是 `tail + 1` 位置描述符缓冲区的数据（这个位置是所有未处理数据中等待时间最长的），处理完这个缓冲区后会把 `tail` 增加一。

- **发送描述符**：
结构体定义：
```c
struct tx_desc
{
  uint64 addr;
  uint16 length;
  uint8 cso;       // checksum offset
  uint8 cmd;       // command field
  uint8 status;    // 
  uint8 css;       // checksum start field
  uint16 special;  // 
};
```
其中 `addr` 和 `length` 的作用和接收描述符的作用相同。除了这两个，主要还需要用到 `cmd` 和 `status` 这两个属性。和接收标志位一样，在 `status` 中需要用到 DD 标志位，表示当前标志位指向的数据是否发送完成。而 `cmd` 描述了传输这个数据包时的一些设置，或者说对于网卡的命令。详情见手册。

- **mbuf**：
为了方便网络数据的处理，xv6 还定义了一个结构体，即 `struct mbuf`，在 `e1000_transmit()` 函数中，我们就需要接收一个 `mbuf` 类型的网络数据，然后写入 DMA 对应的内存地址，进而让网卡发送这个数据。`e1000_init()`使用`mbufalloc()`函数将E1000的mbuf数据包缓冲区分配给DMA。
```c
struct mbuf {
  struct mbuf  *next; // the next mbuf in the chain
  char         *head; // the current start position of the buffer
  unsigned int len;   // the length of the buffer
  char         buf[MBUF_SIZE]; // the backing store
};
```
- 在 `struct mbuf` 结构体中，`len` 表示正文的长度，`head` 表示 headroom 的结束位置。
- 当`net.c`中的网络栈需要发送一个数据包的时候，其会调用`e1000_transmit()`函数，其中的mbuf缓冲区包含了需要被发送的数据包。
- 在 `net.c` 中有很多和 `mbuf` 相关的函数，最主要的就是 `mbufalloc()` 和 `mbuffree()` 分别对应着 `mbuf` 的分配和释放。

对`mbuf`对操作如下：
```c
// The above functions manipulate the size and position of the buffer:
// <- push <- trim
// -> pull -> put
// [-headroom-][------buffer------][-tailroom-]
// |----------------MBUF_SIZE-----------------|
//
// These marcos automatically typecast and determine the size of header structs.
// In most situations you should use these instead of the raw ops above.
#define mbufpullhdr(mbuf, hdr) (typeof(hdr)*)mbufpull(mbuf, sizeof(hdr))
#define mbufpushhdr(mbuf, hdr) (typeof(hdr)*)mbufpush(mbuf, sizeof(hdr))
#define mbufputhdr(mbuf, hdr) (typeof(hdr)*)mbufput(mbuf, sizeof(hdr))
#define mbuftrimhdr(mbuf, hdr) (typeof(hdr)*)mbuftrim(mbuf, sizeof(hdr))
```
其中：
- `mbufpullhdr`用于从缓冲区的起始位置剥离数据（即去除头部数据包）并返回其位置。
- `mbufpushhdr`用于为数据包加上头数据（如ip协议头，udp协议头，eth协议头）。
- `mbufputhdr`用于将数据追加到缓冲区的末尾，并返回指向它的指针。
- `mbuftrimhdr`用于从缓冲区末尾剥离数据并返回指向它的指针。

- **寄存器**：
除了读取和写入RAM中的描述符环外，驱动程序还需要通过E1000的内存映射控制寄存器与E1000交互，以检测接收到的数据包何时可用，并通知E1000驱动程序已在某些发送描述符中填充了要发送的数据包。全局变量regs保存指向E1000的第一个控制寄存器的指针；驱动程序可以通过将regs索引为数组来获取其他寄存器。我们可以通过特定的内存映射访问到 E1000 的控制寄存器。具体来说，是通过 `e1000.c` 中的 `regs` 全局变量加上一些偏移量。在 `e1000_dev.h` 中定义了额这些偏移量。

### Locks
- 由于内核中存在大量的并行数据，例如两个CPU可能同时调用`kalloc`来分配内存，这样就会造成空闲内存列表头同时弹出，从而造成内核中的错误。所以使用互斥锁可以保证在一个时间段只有一个CPU可以持有🔒，以便操作系统可以保护内存数据安全。
XV6中有两种🔒，`spinlock`和`sleep-locks`。
本实验主要是重新设计代码来提高操作系统的并行性。在多核机器上大锁通常是导致并行性差的一个主要。为了提高并行性就需要重新设计数据结构和锁策略来减少锁的竞争。
#### Memory allocator

