- qemu调试：
```shell
终端1:
make qemu-gdb
ctrl a + c查看qemu信息，如：info mem查看内存地址

终端2:
gdb-multiarch kernel/kernel
```
- gdb命令：
```shell
i r pc #查看pc寄存器
x/3i $pc #打印pc所在内存地址的后3条指令，x打印内存值

```
- 进入内核态（通过ecall）
	- 首先找到sh.asm中write的地址打上断点，运行到该处后发现下一条指令就是ecall，如果直接si并不能直接跳入内核，而是要先`i r stvec`然后打上stvec的寄存器地址断点后再si才能进入内核态。（此时进入Trampoline.S，会位于用户不可见的高地址）