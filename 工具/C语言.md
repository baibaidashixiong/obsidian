### 前言
- 在C语言中用`/* */`将代码直接注释掉有时候可能会因为编译器的问题而不能如愿，可以采用以下的方法（与与处理器有关）：
```c
#if 0
	statements
#endif
```
- 常量：
```c
int const *pci; // pci是一个指向整型常量的指针，可以修改指针的值，但不能修改它所指向的值。
int * const cpi; // 声明pci为一个指向整型的常量指针。此时指针是常量，它的值无法修改，但是可以修改它所指向的整型的值。
int const * const cpci; // 指针与所指都是常量，不可修改。
```
### 操作符和表达式
- 位操作：（注：有符号值的右移位操作是不可移植的，因为存在逻辑移位和算术移位）
```c
value = value | 1 << bit_number; // 将指定位设置成1
value = value & ~ ( 1 << bit_number ); // 将指定位清零
value & 1 << bit_number; // 对指定位进行测试，如已被设为1,则结果为非0
```
- 赋值
```c
a = x = y + 3; // 等同于a = ( x = y + 3); <=> x = y + 3; a = x;
r = s + ( t = u - v ) / 3; // 等价于t = u - v; r = s + t / 3;
//以下代码会出错：
//原因是EOF需要的位数(整型，4字节)比字符型(1字节，-128~127)要多，然后被截短的getchar返回值会被拓展与EOF进行比较，导致出错。
char ch;
while(( ch = getchar()) != EOF){...}
```
- 单目操作符：
```c
!取逻辑反，~取补，-取负值，+什么也不干
&操作符产生操作数的地址
int a , *b ;
b = &a; // &取变量a的地址，并把它赋值给指针变量
(float)a //将整型变量a强制转换成对应的浮点数值
>>>
a = b = 10;
c = ++a; //a增至11,c也为11
d = b++; //b增至11,但d仍为10
```
- 条件操作符：
```c
expression1 ? expression2 : expression3;
```
- 逗号操作符：逗号操作符将两个或多个表达式分隔开来，这些表达式自左向右逐个进行求值，整个逗号表达式的值就是最后那个表达式的值。
```c
expression1, expression2, ..., expressionN
>>>
a = get_value();
count_value(a);
while( a > 0 ){
	a = get_value();
	count_value( a );
}
//等价于
while( a = get_value(), count_value( a ), a > 0 ){
	...
}
//更简为
while( count_value( a = get_value() ), a > 0 ){
	...
}
```
- 下标引用和结构成员：
```c
array[n] // 下标引用
*( array + (n) ) // 间接访问，与上面等价
//. 和 ->操作符
s.a访问结构体s中的成员a，->用于访问 结构体指针 中的成员
a->b <=> (*a).b
```
- **左值**(L-value)和**右值**(R-value)：
```c
int a, *pi;
// pi 是左值， &a是右值
pi = &a;
*pi = 20;// 指针pi的值是内存中某个特定位置的地址，*操作符使机器指向那个位置，所以此处左值作为一个表达式（当其作为左值时*pi指定需要进行修改的位置，当其作为右值时它就提取当前存储于这个位置的值）
```
### 指针
- 在硬件中，每一个内存地址都包含着一个值，但是直接记地址太多笨拙，于是在高级语言中就将其抽象成变量，使得可以通过名字而不是地址来访问内存的位置。（注：名字与内存位置之间的关联并不是硬件所提供的，它是由编译器实现的）
- **间接访问操作符**：通过一个指针访问它所指向的地址的过程称为间接访问（indirection）或解引用指针（dereferencing the pointer）这个用于执行间接访问的操作符是单目操作符`*`。
```c
int a = 112, b = -1;
float c = 3.14;
int *d = &a;
float *e = &c;
>>> // 整数交换
/* 
** 交换调用程序中的两个整数
*/
void swap( int *x, int *y ){
	int temp;
	temp = *x;
	*x = *y;
	*y = temp;
}

swap ( &a, &b ); // 调用方法，因为函数期望接受的参数是指针
```
假设a的地址为100，则能得出以下表格：
|  表达式   | 右值  | 类型 |
|  :--:  | :---:  | :--: |
| a  | 112 | int |
| b  | -1 | int |
| c  | 3.14 | float |
| d  | 100 | int `*` |
| e  | 108 | float `*` |
| `*d`  | 112 | int |
| `*e`  | 3.14 | float |
这里的`*d`就是间接访问，`*`就是间接访问操作符。于是语句`*d = 10 - *d;`即等价于`a = 10 - a;`.
解释表达式`*&a = 25;`：将25赋值给变量a，首先&取变量a的地址，使`&a`成为指针常量，然后`*`操作符间接访问其操作数所表示的地址，即变量a。

- **指针初始化**：下列代码会发生内存错误（指针指向非法地址）或是更严重的错误，因为在指针初始化时未对其分配地址，在对其进行赋值的时候指针可能会指向一个合法地址，并将改地址上的值修改。所以在对指针进行间接访问前需要确保其被初始化。
```c
int *a;
*a = 12; // 间接访问
```

- **指针常量**：一般只有在需要访问确定的地址时才使用，如操作系统启动过程中的某个特定地址信息。
```c
*100 = 25; // 非法，间接访问操作只能作用于指针类型表达式
*(int *)100 = 25; // 合法，强制类型转换将100从整型转换为指向整型的指针
```

- **双指针**：`*` 操作符具有从右向左的结合性，所以`int **c`相当于`int *(*c)`，`*c`访问c所指向的位置（即变量b），第二个间接访问操作符访问该位置所指向的地址，即变量a。
```c
int a = 12;
int *b = &a;
int **c = &b; // *c指向b，*(*c)指向a
c = &b; 
```

- **算术运算**：C的指针算术运算只有两种形式：指针 +/- 整数 和 指针 - 指针。两个指针相减的结果类型是ptrdiff_t，它是一种有符号整数类型，减法运算的值是两个指针在内存中的距离（以数组元素的长度为单位，而不是以字节为单位）如指针p1指向`array[i]`，p2指向`array[j]`，则p2-p1的值就是j-i的值。（如果两个指针所指向的不是同一个数组中的元素，则它们之间想减的结果是未定义的）
```c
// 指针 +/- 整数
int *a = &b;
*a++ = 0; // 将a所指地址的内容赋值为0再往后移一个单位，如a为int指针则后移4个字节
```

### 函数
- **函数原型**：函数原型告诉编译器函数的参数数量和每个参数的类型以及返回值的类型，编译器见过原型后，就可以检查该函数的调用，确保参数正确、返回值无误。使用原型最方便且安全的方法是把原型置与一个单独的文件，当其他源文件需要这个函数的原型时就使用 `#include` 指令包含该文件，这样简化了程序的维护任务。（注：当程序调用一个无法见到原型的函数时，编译器便认为该函数返回一个整型值）
```c
//分号区分了函数原型和函数定义的起始部分
int *find_int( int key, int array[], int len ); 
>>>// 使用函数原型的方法，func.c
#include  "func.h"
void a(){
	...
}
void b(){
	...
}
>>> // func.h
int *func( int *value, int len );
```
- **可变参数列表**：
	- 可表参数列表通过 `stdarg.h` 头文件中的stdarg宏来实现，它是标准库的一部分。这个头文件声明了一个类型va_list和`va_start, va_arg, va_end`三个宏。列表参数中的省略号表示此处可能存在传递数量和类型未确定的参数。
	- 函数声明了一个名叫`var_arg`的变量用于访问参数列表的未确定部分，这个变量通过调用`va_start`来初始化。`va_list`类型用于声明一个变量，该变量将依次引用各参数，可以将其理解为“参数指针”类型的变量；`va_start`将参数指针初始化为指向第一个无名参数的指针；`va_arg`每次调用都将返回一个参数，并将参数指针指向下一个参数；`va_end`是必须的，它将完成一些必要的清理工作。
```c
// 计算指定数量的值的平均值
#include <stdatg.h>
float average( int n_values, ... ){
	va_list multiargs;
	int count;
	float sum = 0;
	// 准备访问可变参数
	va_start( multiargs, n_values );
	// 添加取自可变参数列表的值，并为其指定类型
	for( count = 0; count < n_values; count += 1 ){
		sum += va_arg( multiargs, int )
	}
	// 完成处理可变参数
	va_end( var_arg );
	return sum / n_values;
}
```

- **ADT和黑盒**：C可以用于设计和实现**抽象数据类型(ADT, abstract data type)**，也称黑盒。因为其可以限制函数和数据定义的作用域。限制对模块的访问是通过static关键字的合理使用实现的，它可以限制对并非接口的函数和数据的访问。例如维护一个地址/电话号码列表的模块，模块必须提供函数，根据一个指定的名字查找地址和电话号码。但是列表存储的方式是依赖于具体实现的，可以加上static关键字来将其私有，使得外部用户无法直接访问和模块实现有关的数据。

### 数组
#### 一维数组
- C语言中**数组名的值是一个指针常量**，也就是数组第1个元素的地址。只有在两种场合下，数组名并不用指针常量来表示：1. 就是当数组名作为sizeof操作符。 2.单目操作符&的操作数。sizeof返回整个数组的长度，而不是指向数组的指针的长度。
```c
int a[10];
int b[10];
...
c = &a[0];
c = a; // 与上面语句等价，a表示数组a[10]的第一个元素的地址
b = a; // 非法，不能直接复制整个数组，只能循环复制每一个元素
a = c; // 非法，a的值是常量，不能被修改
```
- **指针与下标**：指针**有时**会比使用数组下标更有效率。  （1）  作为数组下标时，为了对下标表达式求值，编译器需要在程序中插入指令，取得a的值，并把它与整型的长度（4字节）相乘，每一次循环相当于`array[addr+1*4]`，该乘法需要花费一定的时间与空间。  （2）  作为指针时，只需要在for循环中的`ap++`时候执行一次乘法`1*4`，而这个乘法只在编译时执行一次，即一条把4与指针相加的指令，程序在运行时候并不需要再执行乘法运算。与固定数字相乘的运算在编译时完成，在运行时所需的指令就更少一些，程序也能更加精简更加有效率。  （3）  两个语句在效率上并没有区别，a可能是任何值，在运行时都需要进行乘法运算。
```c
// 作为数组下标
int array[10], a;
for ( a = 0; a < 10 ; a += 1 )
	array[a] = 0;

// 作为指针
int array[10], *ap;
for ( ap = array; ap < array + 10; ap++ )
	*ap = 0;

// 指针与下表效率相同的场合
>>>
a = get_value();
array[a] = 0;
>>>
a = get_value();
*( array + a ) = 0;
```

- **指针的效率**：比较以下用于数组赋值的代码。第二中运用指针的效率明显高于第一种直接运用数组的效率。
```c
// C代码
#define SIZE 50
int x[SIZE];
int y[SIZE];
int i;
int *p1, *p2;

void try1(){
	for(i = 0; i < SIZE; i++)
		x[i] = y[i];
}

// 汇编代码
_try1:    clrl    _i // 清除变量i的内存位置（=赋值为0）
          jra     L20
L20001:   movl    _i,d0
		  asll    #2,d0 // 左移两位获得地址（ =乘4 ）
		  movl    #_y,a0
		  movl    _i,d1
		  asll    #2,d1
		  movl    #_x,a1
		  movl    a0@(0,d0:L),a1@(0,d1:L) 
		  // a0+d0所指向的值被复制到a1+d1所指向的内存位置
		  addql   #1,_i
L20:      moveq   #50,d0
		  cmpl    _i,d0
		  jgt     L20001
```

```c
// C代码
void try2(){
	register int *p1, *p2; 
	// 对指针使用寄存器变量，汇编代码就可以不必复制指针值
	for( p1 = x, p2 = y; p1 < &x[SIZE];  )
		*p1++ = *p2++;
}
// 汇编代码
_try2:    movl    #_x,a5
		  movl    #_y,a4
		  jra     L40
L20009:   movl    a4@+,a5@+ // 硬件地址自动增量模型
L40:      cmpl    #_x+200,a5 // 相当于源代码的&x[SIZE]
		  jcs     L20009
```

- **字符数组的初始化**：以下两个初始化看上去很像，但是它们具有不同的含义。前者初始化一个字符数组的元素，后者则是一个真正的字符串常量，message2指针变量被初始化为指向这个字符串常量的存储位置。
```c
char message1[] = "Hello";
char *message2 = "Hello";
>>>
message1:
['H' 'e' 'l' 'l' 'o' \0]
>>>
[ message2 ] -> ['H' 'e' 'l' 'l' 'o' \0]
```
#### 多维数组
注：`matrix[4,3]`表示`matrix[3]`，因为逗号操作符首先对第1个表达式求值，但随机丢弃这个值，其可以顺利通过编译。
- **存储顺序**：
```c
int matrix[6][10];
int *mp;
mp = &matrix[3][8];
printf( "First value is %d\n", *mp );   // 打印matrix[3][8]
printf( "Second value is %d\n", *++mp );// 打印matrix[3][9]
printf( "Third value is %d\n", *++mp ); // 打印matrix[4][0]
>>> // 下标
int matrix[3][10];
// 表达式matrix[1][5]访问第2行第6个元素
// matrix指向包含10个整型元素的指针，它指向包含10个整型元素的第1个子数组
// matrix指向包含10个整型元素的指针，它指向包含10个整型元素的第2个子数组
// *(matrix + 1)指向第2个子数组的第1个元素，是一个指向整型的指针
// *(matrix + 1) + 5指向第1行第6个元素，是一个指向整型的指针
// *( *(matrix + 1) + 5 )对上一行中的元素进行间接访问。如果其作为右值使用，就取得存储在该位置的值，如果作为左值使用，这个位置将存储一个新值
*( *( matrix + 1 ) + 5 ) <=> *( matrix[1] + 5 ) <=> matrix[1][5]
```
- **指向数组的指针**：
```c
int vector[10], *vp = vector; // 合法，vp声明为一个指向整型的指针，并把它初始化为指向vector数组的第一个元素
int matrix[3][10], *mp = matrix; // 非法，因为matrix并不是一个指向整型的指针，而是一个指向整型数组的指针。
int (*p)[10] = matrix; // 合法，p是一个指向拥有10个整型元素的数组的指针，其使p指向matrix的第1行。
```


### 字符串、字符和字节
- **字符串长度**：库函数strlen的原型如下：`size_t strlen( char const *string );`。`size_t`是在头文件stddef.h中定义的一个无符号整数类型。下面两个表达式看上去相等，其实不然。
```c
if( strlen( x ) >= strlen( y ) ) ... // 正常工作
if( strlen( x ) - strlen( y ) >= 0 ) ... // 永远为真，因为左边无符号数相减也是无符号数，可以通过强制转换成int来解决
```

- **复制字符串**：函数strcpy原型`char *strcpy( char *dst, char const *src );`，这个函数把参数src字符串复制到dst参数。由于dst参数将进行修改，所以它必须是一个字符数组或者是一个指向动态分配内存的数组的指针，不能使用字符串常量。
```c
// 以下执行完为['D','i','f','f','e','r','e','n','t',0,'e','s','s',a','g','e',0]，第一个NULL字节后面的几个字符再也无法被字符串函数访问
char message[] = "Original message";
...
if( ... )
	strcpy( message, "Different" );
>>>
// 第二个字符串过长会溢出，导致message后未知的内存空间被占用
char message[] = "Original message";
...
if( ... )
	strcpy( message, "A different message" );
```
**字符串查找**：
- **查找一个字符**：`char *strchr(char const *str, int ch);`返回字符ch第1次出现的位置，找到后返回一个指向该位置的指针，找不到则返回NULL；strrchr返回指向字符串中该字符出现最后一次的位置。
- **查找任意几个字符**：`char *strpbrk( char const *str, car const *group );`返回指向str中第1个匹配group中***任意一个***字符的字符位置，未找到则返回NULL指针。（不在标准库中）
- **查找一个子串**：`char *strstr( char const *s1, char const *s2 );`在s1中查找整个s2第1次出现的起始位置，并返回一个指向该位置的指针。否则返回NULL，如果第2个参数为空则返回s1.(不在标准库中)

- **内存操作**：
	- memcpy从src的起始位置复制length个字节到dst的内存起始位置（src和dst不能重叠）；
	- memmove与memcpy类似，但是其源和目标参数可以重叠，但是速度要略慢于memcpy；
	- memcmp对两段内存的内容进行比较，这两段内存分别起始于a和b，共比较length个字节，负值表示a小于b，正值表示a大于b，零表示a等于b。
	- memchr从a的起始位置开始查找字符ch第1次出现的位置，并返回一个指向该位置的指针，共查找length个字节，找不到则返回NULL。
	- memset函数把从a开始的length个字节都设置为字符值ch，`memset(buffer, 0, SIZE);`将前SIZE个字节都初始化为0。
```c
void *memcpy( void *dst, void const *src, size_t length );
void *memmove(void *dst, void const *src, size_t length );
void *memcmp( void const *a, void const *b, size_t length );
void *memchr( void const *a, int ch, size_t length );
void *memset( void *a, int ch, size_t length );
```

### 结构体
- 以下声明创建了y和z，y是一个数组，其包含了20个结构，z是一个指针，它指向这个类型的结构。但是这两个声明被编译器当作两种截然不同的类型，即使它们的成员列表完全相同，所以语句`z = &x;`是非法的。
```c
struct {
	int a;
	char b;
	float c;
} y[20], *z;
// 为结构体提供标签
struct SIMPLE {
	int a;
	char b;
	float c;
};
// 使用标签来声明变量
struct SIMPLE x;
struct SIMPLE y[20], *z;
```
- 使用**typedef**来**创建一种**新的类型：该技巧与声明一个结构标签效果几乎相同，区别在于Simple现在是个类型名而不是个结构标签。
```c
typedef struct {
	int a;
	char b;
	float c;
} Simple;
// 后续声明
Simple x;
Simple y[20], *z;
```

- **结构体成员的直接访问**：结构变量的成员是通过点(.)操作符访问的。点操作符结构两个操作数，左操作数是结构变量的名字，右操作数就是需要访问的成员的名字。这个表达式的结果就是指定的成员。
```c
struct COMPLEX {
	float f;
	int a[20];
	long *lp;
	struct SIMPLE s;
	struct SIMPLE sa[10];
	struct SIMPLE *sp;
}

struct COMPLEX comp;
comp.a; // 选择a成员，结果为数组名
comp.s; // 结构名
(comp.s).a; // 选择结构comp的成员s的成员a，同comp.s.a
( (comp.sa)[4] ).c; // 选择结构体数组元素(comp.sa)[4]的成员c，同表达式comp.sa[4].c 
```
- **结构体成员的间接访问**：`箭头(->)`左边必须为指针，`点号(.)`左边必须为实体。
```c
struct COMPLEX *cp;
(*cp).f <=> cp->f
```
- **结构体的自引用**：第一种自引用是非法的，因为成员b是另一个完整的结构，其内部还包含它自己的成员b，会套娃无限重复下去；第二种自引用是合法的，因为其中b是一个指针而不是结构体，编译器在结构的长度确定之前就已经知道指针的长度。
```c
>>> // 不合法
struct SELF_REF1 {
	int a;
	struct SELF_REF1 b;
	int c;
};
>>> // 合法
struct SELF_REF1 {
	int a;
	struct SELF_REF1 *b;
	int c;
};
>>> // 不合法，因为类型名直到声明的末尾才定义，所以在结构声明的内部其还尚未定义
typedef struct {
	int a;
	SELF_REF3 *b;
	int c;
} SELF_REF3;
>>> // 合法，提前声明b的结构体
typedef struct SELF_REF3_TAG {
	int a;
	struct SELF_REF3_TAG *b;
	int c;
} SELF_REF3;
```

#### 联合
联合的所有成员引用的是**内存中的相同位置**，当想在不同时刻把不同的东西存储在同一位置时就可以使用联合。
```c
union {
	float f;
	int i;
} fi;
```
- 访问联合示例：
```c
struct PARTINFO{
	int cost;
	int supplier;
	...
}; // 零件
struct SUBASSYINFO {
	int n_parts;
	struct {
		char partno[10];
		short quan;
	} parts[MAXPARTS];
}; // 装配件
struct INVREC {
	char partno[10];
	int quan;
	enum { PART, SUBASSY } type;
	union {
		struct PARTINFO part;
		struct SUBASSYINFO subassy;
	} info;
}; // 存货inventory
// 操作名为rec的INVREC结构变量
struct INVREC rec = {...};
if( rec.type == PART ){
	y = rec.info.part.cost;
	z = rec.info.part.supplier;
}
else {
	y = rec.info.subassy.nparts;
	z = rec.info.subassy.parts[0].quan;
}
```
- **联合的初始化**：联合变量可以被初始化，但这个初始值必须是联合第1个成员的类型，而且它必须位于一对的花括号内，以下便将`x.a`初始化为5。如果给出的初始值是任何其他类型，它就会转换为一个整数并赋值给`x.a`。
```c
union {
	int a;
	float b;
	char c[4];
} x = { 5 };
```

### 动态内存分配
- **malloc和free**：malloc分配一块连续的内存，所以它返回的是一个`void *`指针，free的参数要么是NULL，要么是一个先前从malloc、calloc或realloc返回的值。
```c
void *malloc( size_t size );
void free( void *pointer );
```
- **calloc和realloc**：calloc用于分配内存，它与malloc的区别是calloc在返回指向内存的指针之前把它初始化为0；relloc用于修改一个原先已经分配的内存块的大小，使用其可以扩大或缩小内存。如果relloc的第一个参数为NULL，那么它的行为就和malloc一模一样。
```c
void *calloc( size_t num_elements, size_t element_size );
void *realloc( void *ptr, size_t new_size );
```

### 高级指针话题
### 进一步探讨指向指针的指针
- 以下代码进一步探讨双指针和三指针：
	- 问：在一条简单的对i赋值的语句就可以完成任务的情况下，为什么还要使用更为复杂的涉及间接访问的方法呢？
		- 答：如在涉及链表的插入时，函数所拥有的只是一个指向需要修改的内存位置的指针，所以要对该指针进行间接访问操作以访问需要修改的指针变量。
```c
int i;
int *pi;
int **ppi;

ppi = &pi; // 将ppi初始化为指向变量pi，便可以安全的对ppi执行间接访问操作了
*ppi = &i; 
/* 将pi(通过ppi间接访问)初始化为指向向量i，经过以上两条语句变成了：
   i     pi    ppi
  [?]<--[  ]<--[  ] 
*/
// 下面各条语句有相同的效果
i = 'a';
*pi = 'a';
**ppi = 'a'; // 即*(*ppi)
```
- **高级声明**：
```c
int f; /* 一个整型变量 */
int *f; /* f是一个指向整型的指针 */
int* f, g; /* 星号作用于f，f是一个指针，g是一个普通的整型变量 */
int *f(); /* f是一个函数，返回值是类型是一个指向整型的指针 */
int (*f)(); /* f是一个函数指针，指向的函数返回一个整型值，其迫使间接访问在函数调用之前进行 */
int *(*f)(); /* f是一个函数指针， */
```
- **处理命令行参数**：采用双指针来处理参数内容。（注：使用这种方式，命令行参数可能只能处理一次，因为指向参数的指针在内层的f）
```c
/*
** 处理选项参数：跳到下一个参数，并检查它是否以一个横杠开头。
*/
while( *++argv != NULL && **argv == '-' ){
/*
** 检查横杠后面的字母。
*/
 switch( *++*argv ){
	case 'a':
		 option_a = TRUE;
		 break;
	case 'b':
		option_b = TRUE;
		break;
	/* etc. */
 }
 ...
 /* 另一种写法 */
 while(( opt = *++*argv ) != '\0' ){
	 switch( opt ){
		 case 'a':
			 option_a = TRUE;
			 break;
		/* etc. */
	 }
 }
}
```
- **字符串常量**：
```c
/*
  字符串常量本质上是一个指针，即char *类型，所以下面的表达式即"指针值+1"
  结果是个指针，指向字符串中的第2个字符y
*/
"xyz" + 1;
*"xyz"; // 对指针进行间接访问，即该指针指向的字符：x
"xyz"[2]; // 同上，表示字符：z
*( "xyz" + 4 ); // 超出字符串长度，不可预测
/*
** 用于打印*号
** 0-50内每增加5多打印一个星号（星号字符串的指针）
** 如n=5时则从星号字符串的第9个字符开始打印到其结尾
*/
#include <stdio.h>
void mystery( int n ){
	n += 5;
	n /= 10;
	printf("%s\n", "**********" + 10 - n );
	printf("%s\n", &"**********"[ 10 - n ]);//更规范的写法
}
```

### 预处理器
预处理器主要在源代码编译之前对一些文本性质的内容进行操作，它的主要任务包括删除注释、插入被`#include`指令包含的文件的内容、定义和替换由`#define`指令定义的符号以确定代码的部分内容是否应该根据一些条件编译指令进行编译。
- **预处理器定义的符号**：
	- `__FILE__`：进行编译的源文件名。
	- `__LINE__`：文件当前行的行号。
	- `__DATE__`：文件被编译的日期。
	- `__TIME__`：文件被编译的时间。
	- `__STDC__`：如果编译器遵循ANSI C，其值就为1，否则未定义。
- **`#define`**：运用该指令可以把任何文本替换到程序中：下面代码可以方便的插入调试信息。但是更好的实现方式是将它实现为一个函数，后文将会讨论`#define`宏和函数之间的优劣。
```c
/* __FILE__表示进行编译的源文件名，__LINE__表示文件当前行的行号 */
#define DEBUG_PRINT printf( "File %s line %d:" \
						" x=%d, y=%d, z=%d", \
						__FILE__, __LINE__, \
						x, y, z )
```
- **宏与函数**：宏用于执行简单的计算，比如在两个表达式中寻找其中较大的一个（如下）此处相比于函数，用宏的好处是函数的参数必须声明为一种特定的类型，而下面的宏可以用于整型、长整型、单浮点型、双浮点型以及其他任何可以用`>`操作符比较值大小的类型，即**宏是与类型无关**的。   宏的不利之处在于每次使用宏时一份宏定义代码的拷贝都将插入到程序中，容易造成程序长度的大幅度增加。   有些任务无法用函数实现，**宏的参数可以是一种类型**，它无法作为函数参数进行传递。（注：宏还有一个优点就是执行速度快于函数，因为它不存在函数调用/返回的开销，但是使用宏通常会增加程序的长度）
```c
>>> // 返回两个参数中的较大值
#define MAX( a, b )  ((a) > (b) ? (a) : (b) )
>>> 
#define MALLOC(n, type) \
	( (type *)malloc( (n) * sizeof( type )))
pi = MALLOC( 25, int );
// 被预处理器转换为如下语句
pi = ((int *)malloc((25)*sizeof(int)));
```
- **命令行定义**：许多C编译器允许在命令行中定义符号，以用于启动编译过程，在根据同一个源文件编译一个程序的不同版本时，这个特性是很有用的，对于`int array[ARRAY_SIZE];`，使用`-Dname=stuff`可以完成这项任务。`cc -DARRAY_SIZE=100 a.c`可以指定`ARRAY_SIZE=100`。
- **文件包含**：
```c
/* 函数库头文件包含，filename通常以.h后缀为结尾 */
#include <filename>
/* 本地文件包含 */
#include "filename"
// <>为引号的子集，为了区分才用引号
```

### 标准函数库
#### 整型函数
这组函数返回整型值，这些函数分为算术、随机数和字符串转换三类。
- **算术`<stdlib.h>`**：
```c
int abs( int value ); // 返回参数的绝对值
long int labs( long int value ); // 同上，作用对象是长整数
div_t div( int numerator, int denominator ); // 除法运算（2除以1），产生商和余数，在结构体div_t内
ldiv_t ldiv( long int numer, long int denom ); // 作用于长整数
```
- **随机数`<stdlib.h>`：
```c
int rand( void ); // 返回0-RAND_MAX之间的伪随机数
void srand( unsigned int seed ); // 设置随机数种子
```
- **字符串转换`<stdlib.h>`：
```c
int atoi( char const *string ); // 把字符转换为整数
long int atol( char const *string ); // 把字符转换为长整数值
long int strtol( char const *string, char **unused, int base ); // 同样把字符串转换为long，但是strtol保存一个指向转换值后面第1个字符的指针。
unsigned long int stroul( char const *string, char **unused, int base ); // 同上，但是产生一个无符号长整数
```
#### 日期和时间函数
- **处理器时间`<time.h>`**：
```c
clock_t clock( void ); // 返回从程序开始执行起处理器所消耗的时间，在所需要判断代码段的开头和结尾加上再相减
```
- **当天时间`<time.h>`：
```c
time_t time( time_t *returned_value );
```
- **日期和时间的转换`<time.h>`：下面的函数用于操纵`time_t`值：
```c
char *ctime( time_t const *time_value ); // 返回诸如"Wed Feb 10:10:10 2023\n\0"格式的字符串
double difftime( time_t time1, time_t time2 ); // 计算time1-time2点差，并把结果值转换为秒，返回的是一个double类型的值
struct tm *gmtime( time_t const *time_value ); // 把时间转换为结构体tm所表示的时间（世界协调时间）
struct tm *localtime( time_t const *time_value ); // 把时间值转换为当地时间
time_t mktime( struct tm *tm_ptr ); // 把一个tm结构转换为一个time_t值
```
#### 信号
- **信号名`<signal.h>`**：前面四个信号是同步的，最后两个信号是异步的。
| 信号 | 含义 |
| -- | ---- |
| SIGABRT | 程序请求异常终止 |
|SIGFPE|发生一个算术错误|
|SIGILL|检测到非法指令|
|SIGSEGV|监测到对内存的非法访问|
|SIGINT|收到一个交互性注意信号|
|SIGTERM|收到一个终止程序的请求|
- **处理信号`<signal.h>`**：raise函数用于显式地引发一个信号。
```c
int raise( int sig ); // 调用函数将引发它的参数所指定的信号
void ( *signal() )( int ); // signal函数返回一个函数指针，其所指向的函数接受一个整型参数且没有返回值。
signal( int sig, void ( *handler )( int ) ); // sig是上表的信号之一，第2个参数是希望为这个信号设置的信号处理函数，这个处理函数是一个函数指针，其所指向的函数接受一个整型参数且没有返回值。当信号发生时，信号的代码作为参数传递给信号处理函数
void ( *signal( int sig, void ( *handler )( int ) ) )(int); // signal函数返回一个指向该信号以前的处理函数的指针，通过保存这个值，可以为信号设置一个处理函数并在将来恢复为先前的处理函数
```
#### 执行环境
- **断言`<assert.h>`**：断言（假定为真，则为假就停止）在调试程序时候很有用，当它被执行时，这个宏对表达式参数进行测试，如果它的值为假（零），就向标准错误打印一条诊断信息并终止程序。（注：可以在编译时通过定义NDEBUG消除所有断言，编译时使用`-DNDEBUG`或在头文件`<assert.h>`被包含之前增加定义`#define NDEBUG`。
```c
void assert( int expressiong );
```
- **环境`<stdlib.h>`**：`char *getenv( char const *name );`。
- **执行系统命令`<stdlib.h>`**：system函数把它的字符串参数传递给宿主操作系统，这样它就可以作为一条命令由系统的命令处理器执行。
```c
void system( char const *command );
```
#### locale
locale可以使C语言在全世界范围内更通用。