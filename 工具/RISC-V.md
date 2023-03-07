### RISC-V 基础整数指令集
#### RV32I 指令格式
- RISC-V有六种基本指令格式：
	1. R-Type：用于寄存器-寄存器操作的 R 类型指令。Register/register
	2. I-Type：用于短立即数和访存 load 操作的 I 型指令。Immediate
	3. S-Type：用于访存 store 操作的 S 型指令。Store
	4. B-Type：用于条件跳转操作的 B 类型指令。Branch
	5. U-Type：用于长立即数的 U 型指令。Upper immediate
	6. J-Type：用于无条件跳转的 J 型指令。Jump
指令中的rs1, rs2, rd：第一操作数（源寄存器），第二操作数，目的（返回）寄存器。
funct3和funct7决定了操作码的具体执行指令。与操作码结合即成为了指令码。

|  指令   | 含义  |
|  :-----:  | :-----------:  |
| add t1, t2, t3 |Addition: set t1 to (t2 plus t3) |
| addi t1, t2, -100 | Addition immediate: set t1 to (t2 plus signed 12-bit immediate) |
| and t1, t2, t3 | Bitwise AND : Set t1 to bitwise AND of t2 and t3|
| andi t1, t2, -100 |Bitwise AND immediate : Set t1 to bitwise AND of t2 and sign-extended 12-bit immediate|
|auipc t1, 100000 | Add upper immediate to pc: set t1 to (pc plus an upper 20-bit immediate)|
| beq t1, t2, label | Branch if equal : Branch to statement at label's address if t1 and t2 are equal|
| bge t1, t2, label | Branch if greater than or equal: Branch to statement at label's address if t1 is greater than or equal to t2|
| bgeu t1, t2, label | Branch if greater than or equal to (unsigned): Branch to statement at label's address if t1 is greater than or equal to t2 (with an unsigned interpretation)|
| blt t1, t2, label | Branch if less than: Branch to statement at label's address if t1 is less than t2|
| bltu t1, t2, label | Branch if less than (unsigned): Branch to statement at label's address if t1 is less than t2 (with an unsigned interpretation)|
| bne t1, t2, label | Branch if not equal : Branch to statement at label's address if t1 and t2 are not equal|
| csrrc t0, fcsr, t1 | Atomic Read/Clear CSR: read from the CSR into t0 and clear bits of the CSR according to t1|
| csrrci t0, fcsr, 10 | Atomic Read/Clear CSR Immediate: read from the CSR into t0 and clear bits of the CSR according to a constant|
| csrrs t0, fcsr, t1 | Atomic Read/Set CSR: read from the CSR into t0 and logical or t1 into the CSR|
| csrrsi t0, fcsr, 10 | Atomic Read/Set CSR Immediate: read from the CSR into t0 and logical or a constant into the CSR|
|csrrw t0, fcsr, t1 | Atomic Read/Write CSR: read from the CSR into t0 and write t1 into the CSR|
| csrrwi t0, fcsr, 10 | Atomic Read/Write CSR Immediate: read from the CSR into t0 and write a constant into the CSR|
| div t1,t2,t3 |Division: set t1 to the result of t2/t3|
| jal t1, target | Jump and link : Set t1 to Program Counter (return address) then jump to statement at target address |
| jalr t1, t2, -100 | Jump and link register: Set t1 to Program Counter (return address) then jump to statement at t2 + immediate|
| sll t1,t2,t3 | Shift left logical: Set t1 to result of shifting t2 left by number of bits specified by value in low-order 5 bits of t3|
| slli t1,t2,10 | Shift left logical : Set t1 to result of shifting t2 left by number of bits specified by immediate|
| sra t1,t2,t3 | Shift right arithmetic: Set t1 to result of sign-extended shifting t2 right by number of bits specified by value in low-order 5 bits of t3|
| srl t1,t2,t3 | Shift right logical: Set t1 to result of shifting t2 right by number of bits specified by value in low-order 5 bits of t3|
| slt t1,t2,t3 | Set less than : If t2 is less than t3, then set t1 to 1 else set t1 to 0|
| slti t1,t2,-100 | Set less than immediate : If t2 is less than sign-extended 12-bit immediate, then set t1 to 1 else set t1 to 0|

### RISC-V指令详解
- RARS：即RISC-V Assembler, Simulator, and Runtime，将对RISC-V汇编语言程序的执行进行汇编和模拟。它的主要目标是为开始使用RISC-V的人提供一个有效的开发环境。
- 有些指令（jar，bne等）的imm为什么第0位省略？
	- 因为内存中一个内存单元以word（4个字节）为最小单位，一个word的地址一定是4的倍数，所以pc的最小单位为4个字节（0x04，0100），最后一位一定为0.将其省略不但能节省一位空间，还能增加跳转寻址范围。
- 那倒数第二位也为0.
	- 用于兼容c扩展指令的时候可实现2字节对齐。

#### RISC-V逻辑运算
- 逻辑左移：`slli t2, s0, n`。slli使用了改进的I-Type格式。n的最大值为31,因为对应slli指令中只用了5个位来存储imm，即0-31.
- 逻辑右移：`srli t1, t2, n`。向右位移n位，低位舍弃，高位填充为0。t2 除以n并**向下取整**，因为右移会有低地址位小的数被舍弃。
- 算术右移：`srai t2, s0, n`。向右位移n位，低位舍弃，负数高位填充为1，正数填充为0。
- 处理较大数值：`lui t0, 0xff0`。取出立即数0xff0的低无位放入t0的高五位，高位用0补全。t0 = 0x000f f0000。
```c
li s0, 0x00FFFF00 # 伪指令，因为光是imm就包含了32位
>>> 解法1：
lui s0, 0x00FFF
li  s1, 0xF00
or  s0, s0, s1
>>> RARS封装li：
lui s0, 0x01000          # 0x0000 1000取低五位 01000装到s0高五位->0x0100 0000
addi s0, s0, 0xFFFF FF00 # -256 = 0xF00自动补全变为0xFFFF FF00
 0x0100 0000
+0xFFFF FF00
-------------
=0x00FF FF00
```

#### RISC-V循环 分支
- 例1：`A[i] = x;`.
```c
# RISC-V
/*
 *  x<->s3
 *  i<->t0
 *  A[0] = s6
 *  A是32位数字组成的数组
 */
slli t1, t0, 2   # t1 <- 4 * i
add  t2, s6, t1  # t2 <- A + 4 * i
sw   s3, 0(t2)   # A[i] <- x
```
- 例2：`c = naem[k];`.
```c
/*
 *  c<->s0
 *  k<->t0
 *  name[0] = s4
 *  A是8-bit字符组成的数组
 */
add t1, s4, t0    # t1 <- name + k
lb  s3, 0(t1)     # load byte x <- name[k]
```
- 例3：`y = A[B[j]];`.
```c
/*
 *  y<->s3
 *  j<->t0
 *  A[0]<->s6
 *  B[0]<->s7
 *  A和B是32-bit数字组成的数组
 */
slli t1, t0, 2     # t1 <- 4 * j
add  t2, s7, t1    # t2 <- B + 4 * j
lw   t3, 0(t2)     # t3 <- B[j]
slli t4, t3, 2     # t3 <- 4 * B[j]
add  t5, s6, t4    # t5 <- A + 4 * B[j]
lw   s3, 0(t5)     # y <- A[B[j]]
```
##### 循环
- 例：`while(save[i] == k) i = i + j;`.
```c
/*
 *  i<->s3
 *  j<->s4
 *  k<->s5
 *  save[0]<->s6
 *  save是4-bit数字组成的数组
 */
>>> 1.未优化
Loop: slli t1, s3, 2    # t1 <- i * 4
      add  t1, t1, s6   # t1 <- Addr(save[i])
      lw   t0, 0(t1)    # t0 <- save[i]
      bne  t0, s5, Exit # if save[i] != k goto Exit
      add  s3, s3, s4   # i <- i +j
      jal  zero, Loop   # goto Loop
Exit: ebreak
>>> 2.优化后
      slli t1, s3, 2    # t1 <- i * 4
      add  t1, t1, s6   # t1 <- Addr(save[i])
      lw   t0, 0(t1)    # t0 <- save[i]
      bne  t0, s5, Exit # if save[i] != k goto Exit
Loop: add  s3, s3, s4   # i <- i +j
      slli t1, s3, 2    # t1 <- i * 4
      add  t1, t1, s6   # t1 <- Addr(save[i])
      lw   t0, 0(t1)    # t0 <- save[i]
      beq  t0, s5, Loop # if save[i] != k goto Exit
Exit: ebreak
```
#### 其它循环指令
- **Branch on less than**: `blt rs1, rs2, L1`.
```c
/* 
 * {imm, 1b'0}表示将1位0拼接到imm后，即将省略的1bit0补齐。
 * 类似的{imm, 12b'0}表示在imm后补齐12-bit0
 */
if (rs1 < rs2)
	PC <- PC + {imm, 1b'0}
else
	PC <- PC + 4
```
- **Branch on greater than or equal**: `bge rs1, rs2, L1`.
```c
if (rs1 >= rs2)
	PC <- PC + {imm, 1b'0}
else
	PC <- PC + 4
```
#### 条件指令
- **Set less than**: `slt rd, rs1, rs2`.
```c
if (rs1 < rs2)
	rd <- 1;
else
	rd <- 0;
>>> 与beq混合使用：
slt t0, s2, s1    # if (s1 <= s2)
beq t0, zero, L1  # goto L1
```
- **Set less than immediate**: `slti rd, rs1, imm`.
```c
if (rs1 < imm)
	rd <- 1;
else
	rd <- 0;
```

### 返回值，指针
- 调用函数称为caller，被调用函数成为callee。RISC-V中使用ra作为存放返回值的寄存器。
- **寄存器调用规约**：s0-s11为保存寄存器，函数调用时callee必须保持s0-s11的值，callee返回时必须恢复s0-s11的值。t0-t6或a0-a7为临时寄存器，callee可以在不保存的情况下使用t0-t6和a0-a7寄存器。
	- a0-a1：用来传递参数和返回值。
	- a2-a7：用来传递参数。
	- ra存放调用函数返回式的返回地址。
- **内存**：
```bash
# RARS中RISC-V分配的内存划分
		+--------------+<------- sp=0x7FFF FFFC
		|     Stack    |
		|              |
		|              |
		|              |
		| Dynamic data |(heap/malloc e.g.)
		+--------------+<------heap=0x1004 0000
		|              |
		|  Static data |<------- gp=0x1000 8000(global pointer)
		|              |<-----.data=0x1001 0000
		+--------------+<----.extern=0x1000 0000
		|              |
		|     Text     | (code/instruction)
		|              |
		+--------------+<------- pc=0x0040 0000
		|   Reserved   |
		+--------------+<---- 0x0
```
- **frame pointer**：
	- fp最开始指向stack的起始栈底位置。然后sp在新的frame中第一个空的内存区域存放fp的地址`sw fp, 0(sp)`，然后此时将fp移动到sp的位置`mv fp, sp`，此时便可以随意操控sp的位置。
	- 结束时fp读取其指向内存地址中的内容，直接跳转回该地址，便是原caller frame所对应的fp地址。
```bash
保存fp --> 将fp移动至callee frame开头的位置 --> 使用fp来获取stack --> 恢复fp
# sp0表示caller frame的sp，sp指向新的callee frame的第一个空内存地址
	 address         Stack
                     +-----------+
       0x4000 0FF8   |           |
fp-->  0x4000 0FF4   |           | <---+
       0x4000 0FF0   |           |     |---caller frame
sp0->  0x4000 0FEC   |           |     |
	             +-----------+ <---+
sp-->  0x4000 0FF8   |0x4000 0FF4|(store fp address first for recover)
(fp1)	             +-----------+ <---+
       0x4000 0FE4   |           |     |
       0x4000 0FE0   |           |     |---callee frame
sp1->  0x4000 0FDC   |           |     |
	             +-----------+ <---+
       0x4000 0FD8   |           |
       0x4000 0FD4   |           |
       0x4000 0FD0   |           |
		     +-----------+
```
- 无嵌套调用：
```c
>>> c语言
int leaf_example(int g, h ,i, j){
	int f;
	f = (g + h) - (i + j);
	return f;
}
>>> 汇编
/*
 * g<->a0
 * h<->a1
 * i<->a2
 * j<->a3
 * f<->s0
 * 返回结果<->a0
 */
leaf_example:
	addi sp, sp, -4   // grow stack
	sw   s0, 0(sp)    // save s0
	add  t0, a0, a1   // t0 <- g + h
	add  t1, a2, a3   // t1 <- i + j
	sub  s0, t0, t1   // f  <- (g+h) - (i+j)
	add  a0, s0, zero // a0 <-f
	lw   s0, 0(sp)    // restore s0
	addi sp, sp, 4    // shrink stack
	jalr zero, ra, 0  // return
```


### 思考题
- 假设有一个"branch always"(bra)指令，其格式为beq指令并且两个寄存器相同：`beq t0, t0, LABEL`。B-Type指令格式如下。使用RISC-V代码**编写一个IsBra方法**，用于接受存放在a0中的一段beq二进制代码，并且如果是bra指令则返回1,不然返回0.返回值存放在a0中。
```bash
# B-Type指令格式
	+------------+------+------+-----+-----------+----------+
	|31        25|24  20|19  15|14 12|11        7|6        0|
	+------------+------+------+-----+-----------+----------+
	|imm[12|10:5]| rs2  |  rs1 |func3|imm[4:1|11]|    op    |
	+------------+------+------+-----+-----------+----------+
>>>
IsBra:
	srli t0, a0, 15      # t0 <- a0 >> 15
	andi t1, t0, 0x01F   # t1 <- rs1
	srli t2, a0, 20      # t2 <- a0 >> 20
	andi t3, t2, 0x01F   # t2 <- rs2
	beq  t1, t3, braTrue # if rs1 = rs2 goto braTrue
	addi a0, zero, 0     # a0 <- 0
	jalr zero, ra, 0(ret)# return
braTrue:
	addi a0, zero, 1     # a0 <- 1
	jalr zero, ra, 0     # return
```
