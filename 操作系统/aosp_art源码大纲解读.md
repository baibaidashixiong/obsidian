- 源码为art的android-10.0.0_r39分支。
### art核心架构
- art源码中常用的有的dex2oat、compiler、Runtime等。dex2oat存放的主要是dex2oat工具的接口的相关代码，compiler目录存放的是进行aot编译的相关代码；runtime存放的是运行时的相关代码。通过aot技术可以生成.oat文件来加速运行，这部分代码在art/compiler中，而art虚拟机可以通过interpreter和jit技术来运行.dex文件。
### 二、dex2oat工具介绍
#### 2.1 dex2oat入口代码
- `art/dex2oat/dex2oat.cc`。根据dex2oat->IsImage()来选择函数调用路径，这两个路径最终都会走到dex2oat::Compile()函数，dex2oat::Compile()函数的核心代码是创建了一个新的CompilerDriver对象driver_（driver_属于Compilerriver类型的指针`std::unique_ptr<CompilerDriver> driver_;`），这个driver_是通过reset的形式将一个新的CompilerDriver对象设置到driver_中，之后调用了CompileDexFiles()函数。
	- **CompileDexFiles()的具体实现**：通过driver_调用了PreCompile()函数和CompileAll()函数等进行编译dex格式所需要的核心代码
```c++
// dex2oat入口代码流程概述
// 入口
int main(int argc, char** argv) {
  int result = static_cast<int>(art::Dex2oat(argc, argv));

// 调用路径选择
 dex2oat::ReturnCode result;
  if (dex2oat->IsImage()) {
    result = CompileImage(*dex2oat);
  } else {
    result = CompileApp(*dex2oat);
  }

//CompileImage
static dex2oat::ReturnCode CompileImage(Dex2Oat& dex2oat) {
  dex2oat.LoadClassProfileDescriptors();
  jobject class_loader = dex2oat.Compile();

//CompileApp
static dex2oat::ReturnCode CompileApp(Dex2Oat& dex2oat) {
  jobject class_loader = dex2oat.Compile();

//最终都走到dex2oat.Compile(),该函数的核心是将一个新的CompilerDriver对象设置到driver_中
  // Set up and create the compiler driver and then invoke it to compile all the dex files.
  jobject Compile() {
    ClassLinker* const class_linker = Runtime::Current()->GetClassLinker();
...
    driver_.reset(new CompilerDriver(compiler_options_.get(),
                                     compiler_kind_,
                                     thread_count_,
                                     swap_fd_));
...
    return CompileDexFiles(dex_files);
  }

// CompileDexFiles()
  // Create the class loader, use it to compile, and return.
  jobject CompileDexFiles(const std::vector<const DexFile*>& dex_files) {
    ClassLinker* const class_linker = Runtime::Current()->GetClassLinker();
...
    driver_->InitializeThreadPools();
    driver_->PreCompile(class_loader,
                        dex_files,
                        timings_,
                        &compiler_options_->image_classes_,
                        verification_results_.get());
    callbacks_->SetVerificationResults(nullptr);  // Should not be needed anymore.
    compiler_options_->verification_results_ = verification_results_.get();
    driver_->CompileAll(class_loader, dex_files, timings_);
    driver_->FreeThreadPools();
    return class_loader;
  }


```
本小结介绍dex2oat工具的入口函数，并按照入口函数逐层个根据调用关系向下进行代码跟踪，最终跟踪到了driver_的成员函数的调用，driver_的成员函数都是进行dex字节码编译的函数，算是宏观意义上的入口函数，接下来的代码执行就要进入CompilerDriver的实现。
#### 2.2 dex2oat的driver分析
- 上一小结分析到CompilerDriver类成员函数的调用，CompilerDriver类可以被视为dex2oat工具的driver部分。CompilerDriver类的定义和实现位于art/dex2oat/driver的compiler_driver.h和compiler_driver.cc中。其成员函数Precompiler()和CompileAll()的实现都位于compiler_driver.cc中。CompileAll()函数中的核心是对Compiler()函数的调用：
```c++
// CompileAll()函数，核心是调用Compiler()函数
void CompilerDriver::CompileAll(jobject class_loader,
                                const std::vector<const DexFile*>& dex_files,
                                TimingLogger* timings) {
  DCHECK(!Runtime::Current()->IsStarted());
...
  // Compile:
  // 1) Compile all classes and methods enabled for compilation. May fall back to dex-to-dex
  //    compilation.
  if (GetCompilerOptions().IsAnyCompilationEnabled()) {
    Compile(class_loader, dex_files, timings);
  }
  if (GetCompilerOptions().GetDumpStats()) {
    stats_->Dump();
  }
}
```
- Compile()函数也是CompilerDriver类的成员函数，它的主要功能是编译所有可以编译的类和方法，并且这里的编译包含了dex-to-oat和dex-to-dex的编译，所以在调用Compile()函数前需要有编译选项。Compiler()函数的实现，在核心部分两次调用了CompileDexFile()函数，两者不同的地方在于传入的最后一个为回调函数的参数不同，两次分别传入了**CompileMethodQuick**()函数和**CompileMethodDex2Dex**()函数，对应前文的对dex文件的两种方式——将dex格式编译为oat格式或者对dex进行优化。
```c++
void CompilerDriver::Compile(jobject class_loader,
                             const std::vector<const DexFile*>& dex_files,
                             TimingLogger* timings) {
...
  dex_to_dex_compiler_.ClearState();
  for (const DexFile* dex_file : dex_files) {
    CHECK(dex_file != nullptr);
    CompileDexFile(this,
                   class_loader,
                   *dex_file,
                   dex_files,
                   parallel_thread_pool_.get(),
                   parallel_thread_count_,
                   timings,
                   "Compile Dex File Quick",
                   CompileMethodQuick);
    const ArenaPool* const arena_pool = Runtime::Current()->GetArenaPool();
    const size_t arena_alloc = arena_pool->GetBytesAllocated();
    max_arena_alloc_ = std::max(arena_alloc, max_arena_alloc_);
    Runtime::Current()->ReclaimArenaPoolMemory();
  }

  if (dex_to_dex_compiler_.NumCodeItemsToQuicken(Thread::Current()) > 0u) {
    // TODO: Not visit all of the dex files, its probably rare that only one would have quickened
    // methods though.
    for (const DexFile* dex_file : dex_files) {
      CompileDexFile(this,
                     class_loader,
                     *dex_file,
                     dex_files,
                     parallel_thread_pool_.get(),
                     parallel_thread_count_,
                     timings,
                     "Compile Dex File Dex2Dex",
                     CompileMethodDex2Dex);
    }
    dex_to_dex_compiler_.ClearState();
  }

  VLOG(compiler) << "Compile: " << GetMemoryUsageString(false);
}
```
- 上文两次调用了CompileDexFile()函数，并且通过参数的不同为其设置了不同的回调函数，进而完成了dex的两种编译途径的执行。需要注意的是，CompilerDexFile()函数并不是CompilerDriver类的成员函数，而是函数模板，其中类型参数用于最后一个参数，用来接收回调函数。CompileDexFile()函数在具体实现过程中通过context.ForAllLambda()函数发起线程执行编译处理，最终将其操作转入回调函数compile_fn()中：
```c++
template <typename CompileFn>
static void CompileDexFile(CompilerDriver* driver,
                           jobject class_loader,
                           const DexFile& dex_file,
                           const std::vector<const DexFile*>& dex_files,
                           ThreadPool* thread_pool,
                           size_t thread_count,
                           TimingLogger* timings,
                           const char* timing_name,
                           CompileFn compile_fn) {
  TimingLogger::ScopedTiming t(timing_name, timings);
  ParallelCompilationManager context(Runtime::Current()->GetClassLinker(),
                                     class_loader,
                                     driver,
                                     &dex_file,
                                     dex_files,
                                     thread_pool);

  auto compile = [&context, &compile_fn](size_t class_def_index) {
    const DexFile& dex_file = *context.GetDexFile();
    SCOPED_TRACE << "compile " << dex_file.GetLocation() << "@" << class_def_index;
    ClassLinker* class_linker = context.GetClassLinker();
    jobject jclass_loader = context.GetClassLoader();
    ClassReference ref(&dex_file, class_def_index);
    const dex::ClassDef& class_def = dex_file.GetClassDef(class_def_index);
    ClassAccessor accessor(dex_file, class_def_index);
    CompilerDriver* const driver = context.GetCompiler();
...
    // Can we run DEX-to-DEX compiler on this class ?
    optimizer::DexToDexCompiler::CompilationLevel dex_to_dex_compilation_level =
        GetDexToDexCompilationLevel(soa.Self(), *driver, jclass_loader, dex_file, class_def);

    // Compile direct and virtual methods.
    int64_t previous_method_idx = -1;
    for (const ClassAccessor::Method& method : accessor.GetMethods()) {
      const uint32_t method_idx = method.GetIndex();
      if (method_idx == previous_method_idx) {
        // smali can create dex files with two encoded_methods sharing the same method_idx
        // http://code.google.com/p/smali/issues/detail?id=119
        continue;
      }
      previous_method_idx = method_idx;
      compile_fn(soa.Self(),
                 driver,
                 method.GetCodeItem(),
                 method.GetAccessFlags(),
                 method.GetInvokeType(class_def.access_flags_),
                 class_def_index,
                 method_idx,
                 class_loader,
                 dex_file,
                 dex_to_dex_compilation_level,
                 dex_cache);
    }
  };
  context.ForAllLambda(0, dex_file.NumClassDefs(), compile, thread_count);
}
```
- 根据上文可知，CompileDexFile所接收的回调函数为`CompileMethodQuick()`和`CompileMethodDex2Dex()`。其中`CompileMethodQuick()`函数主要通过在内部构建`quick_fn()`函数之后调用`CompileMethodHarness()`函数完成操作，`CompileMethodHarness()`函数调用了`quick_fn()`回调函数。其中`quick_fn()`函数在构建`compiled_method`的时候分为两种：
	- `driver->GetCompiler()->JniCompile()`.
	- `driver->GetCompiler()->Compile()`.
	- `CompileMethodQuick()`函数目的是将dex格式编译为oat格式，代码如下：
```c++
// compiler_driver.cc
static void CompileMethodQuick(
    Thread* self,
    CompilerDriver* driver,
    const dex::CodeItem* code_item,
    uint32_t access_flags,
    InvokeType invoke_type,
    uint16_t class_def_idx,
    uint32_t method_idx,
    Handle<mirror::ClassLoader> class_loader,
    const DexFile& dex_file,
    optimizer::DexToDexCompiler::CompilationLevel dex_to_dex_compilation_level,
    Handle<mirror::DexCache> dex_cache) {
  auto quick_fn = [](
      Thread* self,
      CompilerDriver* driver,
      const dex::CodeItem* code_item,
      uint32_t access_flags,
      InvokeType invoke_type,
      uint16_t class_def_idx,
      uint32_t method_idx,
      Handle<mirror::ClassLoader> class_loader,
      const DexFile& dex_file,
      optimizer::DexToDexCompiler::CompilationLevel dex_to_dex_compilation_level,
      Handle<mirror::DexCache> dex_cache) 
    {
    DCHECK(driver != nullptr);
    CompiledMethod* compiled_method = nullptr;
    MethodReference method_ref(&dex_file, method_idx);

    if ((access_flags & kAccNative) != 0) {
      // Are we extracting only and have support for generic JNI down calls?
      if (!driver->GetCompilerOptions().IsJniCompilationEnabled() &&
          InstructionSetHasGenericJniStub(driver->GetCompilerOptions().GetInstructionSet())) {
        // Leaving this empty will trigger the generic JNI version
      } else {
        // Query any JNI optimization annotations such as @FastNative or @CriticalNative.
        access_flags |= annotations::GetNativeMethodAnnotationAccessFlags(
            dex_file, dex_file.GetClassDef(class_def_idx), method_idx);

        compiled_method = driver->GetCompiler()->JniCompile(
            access_flags, method_idx, dex_file, dex_cache);
        CHECK(compiled_method != nullptr);
      }
    } else if ((access_flags & kAccAbstract) != 0) {
      // Abstract methods don't have code.
    } else {
      const VerificationResults* results = driver->GetCompilerOptions().GetVerificationResults();
      DCHECK(results != nullptr);
      const VerifiedMethod* verified_method = results->GetVerifiedMethod(method_ref);
      bool compile = ...

      if (compile) {
        // NOTE: if compiler declines to compile this method, it will return null.
        compiled_method = driver->GetCompiler()->Compile(code_item,
                                                         access_flags,
                                                         invoke_type,
                                                         class_def_idx,
                                                         method_idx,
                                                         class_loader,
                                                         dex_file,
                                                         dex_cache);
...
      }
      if (compiled_method == nullptr &&
          dex_to_dex_compilation_level !=
              optimizer::DexToDexCompiler::CompilationLevel::kDontDexToDexCompile) {
        DCHECK(!Runtime::Current()->UseJitCompilation());
        // TODO: add a command-line option to disable DEX-to-DEX compilation ?
        driver->GetDexToDexCompiler().MarkForCompilation(self, method_ref);
      }
    }
    return compiled_method;
  };
// 回调quick_fn()
  CompileMethodHarness(self,
                       driver,
                       code_item,
                       access_flags,
                       invoke_type,
                       class_def_idx,
                       method_idx,
                       class_loader,
                       dex_file,
                       dex_to_dex_compilation_level,
                       dex_cache,
                       quick_fn);
}
```
- 类似的，还有CompileMethodDex2Dex()函数对dex格式进行优化，其也是通过新建一个`dex_2_dex_fn()`函数，最终通过`CompileMethodHarness()`函数回调执行`dex_2_dex_fn()`函数。

- 所以调用链为：其中`quick_fn()`返回`compiled_method()`函数，`dex_2_dex_fn()`返回`compiler->CompileMethod()`函数。
```bash
                   +-> CompileMethodQuick()(quick_fn()) --------+
                   |                                            |
CompileDexFile() --+                                            +--> CompileMethodHarness()
                   |                                            |
                   +-> CompileMethodDex2Dex()(dex_2_dex_fn()) --+
```

#### 2.3 dex2oat driver的编译函数
dex2oat的driver部分涉及对method进行编译的3个函数，dex2oat中有关编译的3个函数分别代表着一类编译：
1. `driver->GetCompiler()->JniCompile()`.   将Jni方法编译到oat
2. `driver->GetCompiler()->Compile()`.         将正常的dex编译到oat
3. `compiler->CompileMethod()`.                      将dex编译优化到dex
3个编译函数可以概括为一个Compiler或其子类的JniCompiler()函数的Compile()函数，一个DexToDexCompiler或其子类的CompileMethod()函数。

```c++
// GetCompiler()函数
Compiler* GetCompiler() const {
  return compiler_.get();
}
// compiler_是一个函数指针
std::unique_ptr<Compiler> compiler_;

// compiler_初始化
compiler_.reset(Compiler::Create(*compiler_options, &compiled_method_storage_, compiler_kind));

// GetDexToDexCompiler()函数
optimizer::DexToDexCompiler& GetDexToDexCompiler() {
  return dex_to_dex_compiler_;
}

// dex_to_dex_compiler_是DexToDexCompiler类型
optimizer::DexToDexCompiler dex_to_dex_compiler_;

// Compiler在整个art中只有一个子类OptimizingCompiler
class OptimizingCompiler final : public Compiler {
```

#### 2.4 DexToDexCompiler分析
本结将对dex2oat目录下`DexToDexCompiler`的`CompileMethod()`函数进行具体介绍。`DexToDexCompiler`类的`CompileMethod()`函数主要用于实现从dex到dex格式文件的编译优化。其核心是调用了关键函数`CompilationState::Compile()`和`CompiledMethod::SwapAllocCompiledMethod()`实现其功能，`CompileMethod()`函数的代码如下：
```c++
// dex_to_dex_compiler.cc
CompiledMethod* DexToDexCompiler::CompileMethod(
    const dex::CodeItem* code_item,
    uint32_t access_flags,
    InvokeType invoke_type ATTRIBUTE_UNUSED,
    uint16_t class_def_idx,
    uint32_t method_idx,
    Handle<mirror::ClassLoader> class_loader,
    const DexFile& dex_file,
    CompilationLevel compilation_level) 
    {
...
    bool optimized_return_void;
    {
      CompilationState state(this, unit, compilation_level, existing_quicken_data);
      quicken_data = state.Compile();
      optimized_return_void = state.optimized_return_void_;
    }
...
  CompiledMethod* ret = CompiledMethod::SwapAllocCompiledMethod(
      driver_->GetCompiledMethodStorage(),
      instruction_set,
      ArrayRef<const uint8_t>(),                   // no code
      ArrayRef<const uint8_t>(quicken_data),       // vmap_table
      ArrayRef<const uint8_t>(),                   // cfi data
      ArrayRef<const linker::LinkerPatch>());
  DCHECK(ret != nullptr);
  return ret;
}
```
- `CompilationState::Compile()`的实现也位于`dex_to_dex_compiler.cc`中，它是dex2dex的核心函数，通过switch-case的形式逐条处理dex指令，为后续准备编译完成的方法提供了核心数据，代码如下：
```c++
// CompilationState::Compile()逐条处理dex指令
std::vector<uint8_t> DexToDexCompiler::CompilationState::Compile() {
  DCHECK_EQ(compilation_level_, CompilationLevel::kOptimize);
  const CodeItemDataAccessor& instructions = unit_.GetCodeItemAccessor();
  for (DexInstructionIterator it = instructions.begin(); it != instructions.end(); ++it) {
    const uint32_t dex_pc = it.DexPc();
    Instruction* inst = const_cast<Instruction*>(&it.Inst());

    if (!already_quickened_) {
      DCHECK(!inst->IsQuickened());
    }

    switch (inst->Opcode()) {
      case Instruction::RETURN_VOID:
        CompileReturnVoid(inst, dex_pc);
        break;

      case Instruction::CHECK_CAST:
        inst = CompileCheckCast(inst, dex_pc);
        if (inst->Opcode() == Instruction::NOP) {
          // We turned the CHECK_CAST into two NOPs, avoid visiting the second NOP twice since this
          // would add 2 quickening info entries.
          ++it;
        }
        break;

      case Instruction::IGET:
      case Instruction::IGET_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_QUICK, false);
        break;

      case Instruction::IGET_WIDE:
      case Instruction::IGET_WIDE_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_WIDE_QUICK, false);
        break;

      case Instruction::IGET_OBJECT:
      case Instruction::IGET_OBJECT_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_OBJECT_QUICK, false);
        break;

      case Instruction::IGET_BOOLEAN:
      case Instruction::IGET_BOOLEAN_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_BOOLEAN_QUICK, false);
        break;

      case Instruction::IGET_BYTE:
      case Instruction::IGET_BYTE_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_BYTE_QUICK, false);
        break;

      case Instruction::IGET_CHAR:
      case Instruction::IGET_CHAR_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_CHAR_QUICK, false);
        break;

      case Instruction::IGET_SHORT:
      case Instruction::IGET_SHORT_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IGET_SHORT_QUICK, false);
        break;

      case Instruction::IPUT:
      case Instruction::IPUT_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_QUICK, true);
        break;

      case Instruction::IPUT_BOOLEAN:
      case Instruction::IPUT_BOOLEAN_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_BOOLEAN_QUICK, true);
        break;

      case Instruction::IPUT_BYTE:
      case Instruction::IPUT_BYTE_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_BYTE_QUICK, true);
        break;

      case Instruction::IPUT_CHAR:
      case Instruction::IPUT_CHAR_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_CHAR_QUICK, true);
        break;

      case Instruction::IPUT_SHORT:
      case Instruction::IPUT_SHORT_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_SHORT_QUICK, true);
        break;

      case Instruction::IPUT_WIDE:
      case Instruction::IPUT_WIDE_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_WIDE_QUICK, true);
        break;

      case Instruction::IPUT_OBJECT:
      case Instruction::IPUT_OBJECT_QUICK:
        CompileInstanceFieldAccess(inst, dex_pc, Instruction::IPUT_OBJECT_QUICK, true);
        break;

      case Instruction::INVOKE_VIRTUAL:
      case Instruction::INVOKE_VIRTUAL_QUICK:
        CompileInvokeVirtual(inst, dex_pc, Instruction::INVOKE_VIRTUAL_QUICK, false);
        break;

      case Instruction::INVOKE_VIRTUAL_RANGE:
      case Instruction::INVOKE_VIRTUAL_RANGE_QUICK:
        CompileInvokeVirtual(inst, dex_pc, Instruction::INVOKE_VIRTUAL_RANGE_QUICK, true);
        break;

      case Instruction::NOP:
        if (already_quickened_) {
          const uint16_t reference_index = NextIndex();
          quickened_info_.push_back(QuickenedInfo(dex_pc, reference_index));
          if (reference_index == DexFile::kDexNoIndex16) {
            // This means it was a normal nop and not a check-cast.
            break;
          }
          const uint16_t type_index = NextIndex();
          if (driver_.IsSafeCast(&unit_, dex_pc)) {
            quickened_info_.push_back(QuickenedInfo(dex_pc, type_index));
          }
          ++it;
        } else {
          // We need to differentiate between check cast inserted NOP and normal NOP, put an invalid
          // index in the map for normal nops. This should be rare in real code.
          quickened_info_.push_back(QuickenedInfo(dex_pc, DexFile::kDexNoIndex16));
        }
        break;

      default:
        // Nothing to do.
        break;
    }
  }

  if (already_quickened_) {
    DCHECK_EQ(quicken_index_, existing_quicken_info_.NumIndices());
  }

  // Even if there are no indicies, generate an empty quicken info so that we know the method was
  // quickened.

  std::vector<uint8_t> quicken_data;
  if (kIsDebugBuild) {
    // Double check that the counts line up with the size of the quicken info.
    size_t quicken_count = 0;
    for (const DexInstructionPcPair& pair : instructions) {
      if (QuickenInfoTable::NeedsIndexForInstruction(&pair.Inst())) {
        ++quicken_count;
      }
    }
    CHECK_EQ(quicken_count, GetQuickenedInfo().size());
  }

  QuickenInfoTable::Builder builder(&quicken_data, GetQuickenedInfo().size());
  // Length is encoded by the constructor.
  for (const CompilationState::QuickenedInfo& info : GetQuickenedInfo()) {
    // Dex pc is not serialized, only used for checking the instructions. Since we access the
    // array based on the index of the quickened instruction, the indexes must line up perfectly.
    // The reader side uses the NeedsIndexForInstruction function too.
    const Instruction& inst = instructions.InstructionAt(info.dex_pc);
    CHECK(QuickenInfoTable::NeedsIndexForInstruction(&inst)) << inst.Opcode();
    builder.AddIndex(info.dex_member_index);
  }
  DCHECK(!quicken_data.empty());
  return quicken_data;
}
```

- `CompilationState::Compile()`函数逐条处理完dex指令之后，生成了下一步构建编译完成的方法的核心数据`quicken_data`。`CompilationState::Compile()`函数执行完后，紧接着执行了`CompiledMethod`类的`CompiledMethod::SwapAllocCompiledMethod()`成员函数。`CompiledMethod`类的定义和实现位于`art/compiler`的`compiled_method.h, compiled_method-inl.h`和`compiled_method.cc`中。`CompiledMethod`类用来表示已经编译完成的方法，继承于同个文件中的`CompiledCode`类。`SwapAllocCompiledMethod()`具体代码如下：
```c++
//compiled_method.cc
CompiledMethod* CompiledMethod::SwapAllocCompiledMethod(
    CompiledMethodStorage* storage,
    InstructionSet instruction_set,
    const ArrayRef<const uint8_t>& quick_code,
    const ArrayRef<const uint8_t>& vmap_table,
    const ArrayRef<const uint8_t>& cfi_info,
    const ArrayRef<const linker::LinkerPatch>& patches) {
  SwapAllocator<CompiledMethod> alloc(storage->GetSwapSpaceAllocator());
  CompiledMethod* ret = alloc.allocate(1);
  alloc.construct(ret,
                  storage,
                  instruction_set,
                  quick_code,
                  vmap_table,
                  cfi_info, patches);
  return ret;
}
```

- `SwapAllocCompiledMethod()`函数最终调用了`swap_space.h`中`SwapAllocator`的`construct()`函数，`SwapAllocCompiledMethod()`函数通过调用`SwapAllocator`的`construct()`函数完成了一个新构建的`CompiledMethod`，这样就完成了一种从dex到dex的编译方法。至此梳理了dex2oat中的dex2dex的执行流程。
```c++
// swap_space.h
  void construct(pointer p, const_reference val) {
    new (static_cast<void*>(p)) value_type(val);
  }
  template <class U, class... Args>
  void construct(U* p, Args&&... args) {
    ::new (static_cast<void*>(p)) U(std::forward<Args>(args)...);
  }
```

### 三、OptimizingCompiler介绍
### 五、ART启动分析
art提供的功能全部封装在一个libart.so库中，并且Dalvik对外提供三个接口：
1. `JNI_GetDefaultJavaVMInitArgs`:
2. `JNI_CreateJavaVM`:
3. `JNI_GetCreatedJavaVMs`:
#### 5.1 ART启动中的虚拟机启动一
ART指的是整个运行时体系，包括了虚拟机、编译器、dex2oat工具等众多内容。
- ART是Android的运行时，其内部还包含一个虚拟机用于指令的执行。ART是由Zygote进程所启动的，Zygote所对应的启动代码位于frameworks/base/cmds/app_process/app_main.cpp中的`main()`函数，这里的`main()`函数通过构建一个新的AppRuntime对象，然后调用其start()函数来启动运行时：
	1. AppRuntime类继承于AndroidRuntime类，它的定义和实现同样位于`frameworks/base/cmds/app_process/app_main.cpp`，其并没有重新start()函数。AndroidRuntime类的定义和实现位于`frameworks/base/core/jni/AndroidRuntime.cpp`中。AndroidRuntime的start()函数位于AndroidRuntime.cpp中，它用于启动ART，其核心内容是通过调用JniInvocation的Init()函数准备相关内容，再通过AndroidRuntime的startVm()函数启动虚拟机。
	2. JniInvocation的`Init()`函数实现位于`libnativehelper/include/nativehelper/JniInvocation.h`中，主要用于初始化Jni调用的API。
		- 其中impl_是一个JniInvocationImpl类型的指针，并且在构造函数中进行了初始化，其指向了一个新建的JniInvocationImpl对象。
	3. JniInvocationCreate()函数的实现位于`libnativehelper/JniInvocation.cpp`中。在明确了impl_之后，`libnativehelper/JniInvocation.cpp`中的`JniInvocationInit()`函数将对library初始化，转化为使用impl_的Init()函数对library进行初始化。
		- 其中的instance是JniInvocationImpl类型的指针，JniInvocation的Init()函数最终被转化为`libnativehelper/JniInvocation.cpp`中的`JniInvocationImpl::Init`函数通过`GetLibrary()`函数获取库，并且通过`OpenLibrary()`函数打开库，然后通过`FindSymbol`将`JNI_GetDefaultJavaVMInitArgs()`函数挂载到`JNI_GetDefaultJavaVMInitArgs_`，`JNI_CreateJavaVM()`挂载到`JNI_CreateJavaVM_`，`JNI_GetCreatedJavaVMs()`挂载到`JNI_GetCreatedJavaVMs_`。
	4. 启动ART时默认传递的library是NULL，在GetLibrary的时候，如library为空，则会将libart.so传递给library，所以是从libart.so库中寻找`JNI_GetDefaultJavaVMInitArgs(), JNI_CreateJavaVM()`和`JNI_GetCreatedJavaVMs()`函数，这三个函数都位于`art/Runtime/jni/java_vm_ext.cc`中，**这样就进入了ART的源码目录**。Init过程结束后进行的是启动虚拟机的过程，AndroidRuntime的startVM()函数的实现位于`frameworks/base/core/jni/AndroidRuntime.cpp`中，通过`JNI_CreateJavaVM()`函数启动Dalvik虚拟机。
		- 其中的`JNI_CreateJavaVM()`函数指的是`libnativehelper/JniInvocation.cpp`中的`JNI_CreateJavaVM()`函数，`JniInvocation.cpp`中的`JNI_CreateJavaVM()`函数将调用转到`JniInvocationImpl::JNI_CreateJavaVM()`函数中，最终调用了`JNI_CreateJavaVM_()`函数，即在`JniInvocationImpl::Init()`环节挂载的`art/Runtime/jni/java_vm_ext.cc`中的`JNI_CreateJavaVM()`函数。
```c++
// frameworks/base/cmds/app_process/app_main.cpp
// Zygote初始化启动流程
int main(int argc, char* const argv[])
{
    AppRuntime runtime(argv[0], computeArgBlockSize(argc, argv));
...
    if (zygote) {
        runtime.start("com.android.internal.os.ZygoteInit", args, zygote);
    } else if (className) {
        runtime.start("com.android.internal.os.RuntimeInit", args, zygote);
    } 
...
}


//  frameworks/base/core/jni/AndroidRuntime.cpp
//  先通过JniInvocation的start准备相关内容，再通过AndroidRuntime的startVm()函数启动虚拟机
void AndroidRuntime::start(const char* className, const Vector<String8>& options, bool zygote)
{
...
    /* start the virtual machine */
    JniInvocation jni_invocation;
    jni_invocation.Init(NULL);
    JNIEnv* env;
    if (startVm(&mJavaVM, &env, zygote) != 0) {
        return;
    }
    onVmCreated(env);
...
}


// libnativehelper/include/nativehelper/JniInvocation.h
// 初始化Jni的Init
  bool Init(const char* library) {
    return JniInvocationInit(impl_, library) != 0;
  }


// impl_初始化
JniInvocationImpl* impl_;

  JniInvocation() {
    impl_ = JniInvocationCreate();
  }

MODULE_API JniInvocationImpl* JniInvocationCreate() {
  return new JniInvocationImpl();
}


// JniInvocationInit
MODULE_API int JniInvocationInit(JniInvocationImpl* instance, const char* library) {
  return instance->Init(library) ? 1 : 0;
}


// JniInvocationImpl::Init
bool JniInvocationImpl::Init(const char* library) {
...
  library = GetLibrary(library, buffer);
  handle_ = OpenLibrary(library);
...
  if (!FindSymbol(reinterpret_cast<FUNC_POINTER*>(&JNI_GetDefaultJavaVMInitArgs_),
                  "JNI_GetDefaultJavaVMInitArgs")) {
    return false;
  }
  if (!FindSymbol(reinterpret_cast<FUNC_POINTER*>(&JNI_CreateJavaVM_),
                  "JNI_CreateJavaVM")) {
    return false;
  }
  if (!FindSymbol(reinterpret_cast<FUNC_POINTER*>(&JNI_GetCreatedJavaVMs_),
                  "JNI_GetCreatedJavaVMs")) {
    return false;
  }
  return true;
}


// frameworks/base/core/jni/AndroidRuntime.cpp
// JNI_CreateJavaVM()启动Dalvik虚拟机
/*
 * Start the Dalvik Virtual Machine.
 *
 * Various arguments, most determined by system properties, are passed in.
 * The "mOptions" vector is updated.
 *
 * CAUTION: when adding options in here, be careful not to put the
 * char buffer inside a nested scope.  Adding the buffer to the
 * options using mOptions.add() does not copy the buffer, so if the
 * buffer goes out of scope the option may be overwritten.  It's best
 * to put the buffer at the top of the function so that it is more
 * unlikely that someone will surround it in a scope at a later time
 * and thus introduce a bug.
 *
 * Returns 0 on success.
 */
int AndroidRuntime::startVm(JavaVM** pJavaVM, JNIEnv** pEnv, bool zygote)
{
...
    /*
     * Initialize the VM.
     *
     * The JavaVM* is essentially per-process, and the JNIEnv* is per-thread.
     * If this call succeeds, the VM is ready, and we can start issuing
     * JNI calls.
     */
    if (JNI_CreateJavaVM(pJavaVM, pEnv, &initArgs) < 0) {
        ALOGE("JNI_CreateJavaVM failed\n");
        return -1;
    }
    return 0;
}


// libnativchelper/../JniInvocation.cpp
MODULE_API jint JNI_CreateJavaVM(JavaVM** p_vm, JNIEnv** p_env, void* vm_args) {
  // Ensure any cached heap objects from previous VM instances are
  // invalidated. There is no notification here that a VM is destroyed. These
  // cached objects limit us to one VM instance per process.
  JniConstants::Uninitialize();
  return JniInvocationImpl::GetJniInvocation().JNI_CreateJavaVM(p_vm, p_env, vm_args);
}

jint JniInvocationImpl::JNI_CreateJavaVM(JavaVM** p_vm, JNIEnv** p_env, void* vm_args) {
  return JNI_CreateJavaVM_(p_vm, p_env, vm_args);
}
```

至此，Dalivk虚拟机就启动成功了，ART内部关于虚拟机启动的相关代码可以从`art/Runtime/jni/java_vm_ext.cc`中的`JNI_CreateJavaVM()`函数开始继续向下跟踪。
梳理一下：
```bash
1. frameworks/base/.../app_main.cpp:    int main()
   |
   |
   +-> frameworks/base/.../AndroidRuntime.cpp:  AppRuntime start() # 用于启动ART
       |
       |
2.     +-> libnativehelper/.../JniInvocation.h: JniInvocation init() #用于初始化Jni的API
           |
           +-> JniInvocationImpl* impl_--> JniInvocationCreate()
           |
3.         +-> libnativehelper/.../JniInvocation.cpp: JniInvocationImpl:Init 
               |  # 对library进行初始化，寻找动态库并注册art中的JNI_CreateJavaVM()等函数，以便进入art源码目录
               |
4.             +-> art/runtime/jni/java_vm_ext.cc: JNI_CreateJavaVM()
```



#### 5.2 ART启动中的虚拟机启动二
上节进入了`art/runtime/jni/java_vm_ext.cc`（ext:extension）中的`JNI_CreateJavaVM()`函数。本小节将从该函数继续向下跟踪。`java_vm_ext.cc`中的`JNI_CreateJavaVM()`函数通过`Runtime::Create()`函数构建一个新的Runtime，然后通过Runtime调用其Start()函数。
1. Runtime类的实现位于`art/runtime/runtime.cc`中，它的`Create()`函数有两个实现，其中双输入参数的实现最终被转换为对Runtime类的`ParseOptions()`函数和1个参数版本实现的调用，单参数输入的函数最终调用了`Init()`函数，其中`Init()`函数主要用于对Runtime进行初始化。
	- `JNI_CreateJavaVM()`函数中，在Runtime的Create()函数执行之后还调用了Start()函数，也就是完成了Runtime的创建和初始化之后进行了Runtime对象的启动。`Runtime::Start()`函数中涉及的内容将会在后文进行详细介绍。
	- Runtime在Start()函数执行完之后，就被认为已经启动成功了，也就是说只要Java虚拟机启动成功，ART的核心部分就启动成功了。
```c++
// java_vm_ext.cc
extern "C" jint JNI_CreateJavaVM(JavaVM** p_vm, JNIEnv** p_env, void* vm_args) {
...
  if (!Runtime::Create(options, ignore_unrecognized)) {
    return JNI_ERR;
  }
...
  Runtime* runtime = Runtime::Current();
  bool started = runtime->Start();
  if (!started) {
    delete Thread::Current()->GetJniEnv();
    delete runtime->GetJavaVM();
    LOG(WARNING) << "CreateJavaVM failed";
    return JNI_ERR;
  }

  *p_env = Thread::Current()->GetJniEnv();
  *p_vm = runtime->GetJavaVM();
  return JNI_OK;
}


// runtime.cc
// 单参数和双参数的Create()函数
bool Runtime::Create(RuntimeArgumentMap&& runtime_options) {
  // TODO: acquire a static mutex on Runtime to avoid racing.
  if (Runtime::instance_ != nullptr) {
    return false;
  }
  instance_ = new Runtime;
  Locks::SetClientCallback(IsSafeToCallAbort);
  if (!instance_->Init(std::move(runtime_options))) {
    // TODO: Currently deleting the instance will abort the runtime on destruction. Now This will
    // leak memory, instead. Fix the destructor. b/19100793.
    // delete instance_;
    instance_ = nullptr;
    return false;
  }
  return true;
}

bool Runtime::Create(const RuntimeOptions& raw_options, bool ignore_unrecognized) {
  RuntimeArgumentMap runtime_options;
  return ParseOptions(raw_options, ignore_unrecognized, &runtime_options) &&
      Create(std::move(runtime_options));
}


// runtime.cc
// Runtime::Start()
bool Runtime::Start() {
...
  // Create the JIT either if we have to use JIT compilation or save profiling info. This is
  // done after FinishStartup as the JIT pool needs Java thread peers, which require the main
  // ThreadGroup to exist.
  //
  // TODO(calin): We use the JIT class as a proxy for JIT compilation and for
  // recoding profiles. Maybe we should consider changing the name to be more clear it's
  // not only about compiling. b/28295073.
  if (jit_options_->UseJitCompilation() || jit_options_->GetSaveProfilingInfo()) {
    // Try to load compiler pre zygote to reduce PSS. b/27744947
    std::string error_msg;
    if (!jit::Jit::LoadCompilerLibrary(&error_msg)) {
      LOG(WARNING) << "Failed to load JIT compiler with error " << error_msg;
    }
    CreateJitCodeCache(/*rwx_memory_allowed=*/true);
    CreateJit();
  }

  // Send the start phase event. We have to wait till here as this is when the main thread peer
  // has just been generated, important root clinits have been run and JNI is completely functional.
  {
    ScopedObjectAccess soa(self);
    callbacks_->NextRuntimePhase(RuntimePhaseCallback::RuntimePhase::kStart);
  }

  system_class_loader_ = CreateSystemClassLoader(this);

  if (!is_zygote_) {
    if (is_native_bridge_loaded_) {
      PreInitializeNativeBridge(".");
    }
    NativeBridgeAction action = force_native_bridge_
        ? NativeBridgeAction::kInitialize
        : NativeBridgeAction::kUnload;
    InitNonZygoteOrPostFork(self->GetJniEnv(),
                            /* is_system_server= */ false,
                            action,
                            GetInstructionSetString(kRuntimeISA));
  }

  StartDaemonThreads();

  // Make sure the environment is still clean (no lingering local refs from starting daemon
  // threads).
  {
    ScopedObjectAccess soa(self);
    self->GetJniEnv()->AssertLocalsEmpty();
  }

  // Send the initialized phase event. Send it after starting the Daemon threads so that agents
  // cannot delay the daemon threads from starting forever.
  {
    ScopedObjectAccess soa(self);
    callbacks_->NextRuntimePhase(RuntimePhaseCallback::RuntimePhase::kInit);
  }

  {
    ScopedObjectAccess soa(self);
    self->GetJniEnv()->AssertLocalsEmpty();
  }

  VLOG(startup) << "Runtime::Start exiting";
  finished_starting_ = true;

  if (trace_config_.get() != nullptr && trace_config_->trace_file != "") {
    ScopedThreadStateChange tsc(self, kWaitingForMethodTracingStart);
    Trace::Start(trace_config_->trace_file.c_str(),
                 static_cast<int>(trace_config_->trace_file_size),
                 0,
                 trace_config_->trace_output_mode,
                 trace_config_->trace_mode,
                 0);
  }

  // In case we have a profile path passed as a command line argument,
  // register the current class path for profiling now. Note that we cannot do
  // this before we create the JIT and having it here is the most convenient way.
  // This is used when testing profiles with dalvikvm command as there is no
  // framework to register the dex files for profiling.
  if (jit_.get() != nullptr && jit_options_->GetSaveProfilingInfo() &&
      !jit_options_->GetProfileSaverOptions().GetProfilePath().empty()) {
    std::vector<std::string> dex_filenames;
    Split(class_path_string_, ':', &dex_filenames);
    RegisterAppInfo(dex_filenames, jit_options_->GetProfileSaverOptions().GetProfilePath());
  }

  return true;
}
```

#### 5.3 ART启动中的JIT编译器的创建
Dalvik虚拟机中包含了JIT编译器，在ART启动阶段中也会创建一个JIT编译器。上一小结中的`Runtime::Start()`函数中包含了对JIT编译器的创建，以便保障运行时需要进行JIT编译的时候有对应的编译器可用。
```c++
void Runtime::CreateJit() {
  if (jit_code_cache_.get() == nullptr) {
    if (!IsSafeMode()) {LOG(WARNING) << "Missing code cache, cannot create JIT.";}return;}
  if (IsSafeMode()) {
    LOG(INFO) << "Not creating JIT because of SafeMode.";
    jit_code_cache_.reset();return;}

  jit::Jit* jit = jit::Jit::Create(jit_code_cache_.get(), jit_options_.get());
  DoAndMaybeSwitchInterpreter([=](){ jit_.reset(jit); });
  if (jit == nullptr) {
    LOG(WARNING) << "Failed to allocate JIT";
    // Release JIT code cache resources (several MB of memory).
    jit_code_cache_.reset();
  } else {
    jit->CreateThreadPool();
  }
}
```

其中Jit::Create()函数的实现位于`art/Runtime/jit/jit.cc`中，是Jit类的成员函数。它通过对jit_load_()函数的执行创建了一个新的`JitCompiler(jit_compiler_handler_)`，并且该JitCompiler的_compiler变量被设置成一个新建的OptimizingCompiler。之后还新建了一个Jit类。其中的`jit_load_()`函数是通过`Runtime::Start()`函数中调用的`Jit::LoadCompilerLibrary()`函数进行挂载的，其实际函数位于`art/compiler/jit/jit_compiler.cc`文件中。`JitCompiler::Create()`通过调用JitCompiler类的构造函数来生成新的Jitcompiler对象。
- `JitCompiler::JitCompiler() -> Compiler* Compiler::Create() -> Compiler* CreateOptimizingCompiler() -> new OptimizingCompiler()`，也就是说JitCompiler中的compiler_指针指向一个新建的OptimizingCompiler对象，有关OptimizingCompiler的相关内容见第三节。
- 这里涉及的JitCompiler最终还是一个OptimizingCompiler。它们都是`art/compiler`部分的内容，所以在`Jit::LoadCompilerLibrary()`函数中加载的也是`libartd-compiler.so`。
```c++
extern "C" JitCompilerInterface* jit_load() {
  VLOG(jit) << "Create jit compiler";
  auto* const jit_compiler = JitCompiler::Create();
  CHECK(jit_compiler != nullptr);
  VLOG(jit) << "Done creating jit compiler";
  return jit_compiler;
}

// JitCompiler::Create()通过调用JitCompiler类的构造函数来生成新的Jitcompiler对象
JitCompiler* JitCompiler::Create() {
  return new JitCompiler();
}

// JitCompiler()类
class JitCompiler : public JitCompilerInterface {...}

// JitCompiler::JitCompiler()构造函数
JitCompiler::JitCompiler() {
  compiler_options_.reset(new CompilerOptions());
  ParseCompilerOptions();
  compiler_.reset(
      Compiler::Create(*compiler_options_, /*storage=*/ nullptr, Compiler::kOptimizing));
}
// 析构函数，在对应的构造函数被销毁时候调用
JitCompiler::~JitCompiler() {
  if (compiler_options_->GetGenerateDebugInfo()) {
    jit_logger_->CloseLog();
  }
}

// optimizing_compiler.cc OptimizingCompiler
Compiler* CreateOptimizingCompiler(const CompilerOptions& compiler_options,
                                   CompiledMethodStorage* storage) {
  return new OptimizingCompiler(compiler_options, storage);
}
```

#### 5.4 ART启动中的Thread处理

### 六、ART的执行
ART启动完成之后就进入了正常的运行状态，在运行状态下，会根据所要运行的App的不同情况为App选取不同的形式去执行。
#### 6.1 ART运行基本流程
根据要执行的App的输入格式，以及具体执行过程中的情况，ART的运行可以有多个流程进行选择。在ART上运行的App通常会将两种格式的执行文件提交给ART，分别是.oat格式和.dex格式。.oat格式文件通过dex2oat工具将.dex进行编译所得。这两种格式的文件在ART运行的时候是在不同的流程中进行处理的。.oat格式的文件因为是提前编译过的OAT二进制格式文件，所以交给ART之后会走直接执行的流程，通过运行时直接执行OAT中已经编译好的方法直至App结束；.dex格式的文件交给ART之后，ART会将dex这种中间语言放到解释器进行解释执行或者交给JIT编译器进行即使编译之后执行。
无论ART接收的是.oat格式还是.dex格式的App，它们在ART上执行的时候都会按照方法逐个去执行。.oat格式文件是编译过的所以会直接执行；对于.dex格式文件，如果是JIT编译过的方法可以从cache中取出直接执行，没有编译过的方法则交给解释器执行，通过根据是否为hot代码来触发JIT编译条件。
```bash
.oat files --(using aot binary)------->  ART  ------>+
                                                     |
                                                     |
	                            +-->interpreter----->+-->App runs
                                |                    |
                                |(cold code)         |
                                |                    |
.dex files--(no aot binary)--> ART                   |
                                |                    |
                                |(hot code)          |
                                |                    |
                            Just-in-Time(JIT)------->+
```
#### 6.2 Zygote进程调用应用程序
用ART执行的过程中Zygote进程会创建新的进程，然后该进程会通过命令去调用应用程序。
- Zygote进程会运行ZygoteServer类的`runSelectLoop()`函数，在`runSelectLoop()`函数中会根据socket发来的消息为即将运行的应用创建一个新的进程，这是ART开始运行，App开始运行在ART之上的入口。`runSelectLoop()`函数中所调用的`ZygoteConnection.processOneCommand()`函数实现了根据socket信息新建子进程的功能，`processOneCommand()`函数位于`frameworks/base/core/java/com/android/internal/os/ZygoteConnection.java`中，`ZygoteConnection.processOneCommand()`函数中重要的函数主要有`forkAndSpecialize()`和`handleChildProc()`两个函数。

#### 6.5 方法的执行
无论是oat格式还是解释器模式都将根据方法的入口点进行执行。
- .oat格式文件作为被dex2oat编译之后的二进制文件，它其中的方法可以被**直接执行**，即在ART中直接按照方法逐个进行执行。
- **解释执行**的时候输入的dex2dex编译器是处理后的dex文件。ART虚拟机支持解释方式执行dex字节码，这部分功能从ART源码结构的角度来看，它们被封装在一个名为mterp (modular interpreter) 的模块中（目录`runtime/interpreter/mterp`中）。它在不同的CPU平台上会利用对应的汇编指令来编写dex字节码的处理。使用汇编来编写代码可大幅度提升执行速度。在dalvik虚拟机时代也有mterp这个模块，但除了几个主流CPU平台上有汇编实现外还存在一个用C++实现的代码比较有参考价值，而在ART虚拟机的mterp模块里C++实现的代码被去掉了，只留下不同CPU平台上的汇编实现。
	- `mterp_current_ibase`表示当前正在使用的interpreter处理的入口地址；`mterp_default_ibase`表示默认的interpreter处理入口地址；`mterp_alt_ibase`表示可追踪执行情况的interpreter地址；这3个变量都是指向汇编代码中interpreter处理的入口函数。代码中会根据实际情况将`mterp_current_ibase`指向其它两个变量。如果设置了跟踪每条指令解释执行的情况，则`mterp_current_ibase`指向`mterp_alt_ibase`，否则指向`mterp_default_ibase`。
##### JIT编译执行
**JIT编译**是在运行的时候将原本计划用于解释执行的代码编译成二进制代码进行执行。目前常见的JIT编译主要有基于方法的JIT、基于踪迹的JIT和基于区域的JIT等。当前ART的JIT编译所采用的是**基于方法的JIT**。
- **基于方法的JIT**是**以方法作为一个编译单元进行JIT编译**的，很多经典的JIT编译是基于方法的，这是因为方法作为一个编译但与那有着较高的独立性。在ART中，JIT编译所涉及的流程主要有两个。第1个是在程序执行的过程中遇到已经使用JIT编译器编译过的方法，可以直接执行；第2个是在遇到未编译过的方法时需要判定是否为热代码，如果为热代码则进行JIT编译，然后放到JIT代码缓存里（JIT Code Cache），为接下来的执行做好准备。JIT编译的过程所真正能体现的地方是在将热代码进行JIT编译这个过程中，也就是上面提到的第2个流程。从代码实现层面进行分析，解释器的实现代码中有一个重要的函数，即`Execute()`函数，它的实现位于`art/runtime/interpreter/interpreter.cc`中，主要负责方法的执行，这里面涉及了JIT编译、执行和解释执行，所以在解释器中进行JIT编译和执行过程也体现在这个函数中，该函数中最重要的函数是`Jit::MethodEntered()`函数和`ArtInterpreterToCompiledCodeBridge()`函数，前者对方法进行JIT编译，后者则是从解释器到已经编译的代码的桥梁，也可以理解为从解释器调用已经由JIT编译过的代码。
	- `Jit::MethodEntered()`函数的实现位于`art/runtime/jit/jit.cc`中，它会通过`JitCompilerTask`的`Run()`函数或者`AddSamples()`函数最终调用`Jit::CompileMethod()`函数，去实现对于方法的JIT编译。
		- `Jit::CompileMethod()`函数是JIT编译方法的一个入口函数，它通过调用JIT编译器对方法进行编译。它通过`jit_compile_method_()`函数进行的JIT编译，而`jit_compile_method_()`函数绑定的是libart-compiler.so中的`jit_compile_method()`函数，该函数属于JIT编译器的内容，它的实现位于`art/compiler/jit/jit_compiler.cc`中。`jit_compile_method()`内部的JIT编译过程是通过`compiler_->JitCompile()`实现的JIT编译。
			- 这里的`compiler_`是`std::unique_ptr<Compiler>`类型，并且在JitCompiler的构造函数中进行了重置。`compiler_`被重置为一个新建立的OptimizingCompiler对象，所以`compiler_->JitCompile()`在实际的执行中执行的是OptimzingCompiler的JitCompiler()函数。
```c++
// interpreter.cc
static inline JValue Execute(
    Thread* self,
    const CodeItemDataAccessor& accessor,
    ShadowFrame& shadow_frame,
    JValue result_register,
    bool stay_in_interpreter = false,
    bool from_deoptimize = false) REQUIRES_SHARED(Locks::mutator_lock_) {
  DCHECK(!shadow_frame.GetMethod()->IsAbstract());
  DCHECK(!shadow_frame.GetMethod()->IsNative());
  // Check that we are using the right interpreter.
  if (kIsDebugBuild && self->UseMterp() != CanUseMterp()) {
    // The flag might be currently being updated on all threads. Retry with lock.
    MutexLock tll_mu(self, *Locks::thread_list_lock_);
    DCHECK_EQ(self->UseMterp(), CanUseMterp());
  }

  if (LIKELY(!from_deoptimize)) {  // Entering the method, but not via deoptimization.
  ...
    if (!stay_in_interpreter && !self->IsForceInterpreter()) {
      jit::Jit* jit = Runtime::Current()->GetJit();
      if (jit != nullptr) {
        jit->MethodEntered(self, shadow_frame.GetMethod());
        if (jit->CanInvokeCompiledCode(method)) {
          JValue result;

          // Pop the shadow frame before calling into compiled code.
          self->PopShadowFrame();
          // Calculate the offset of the first input reg. The input registers are in the high regs.
          // It's ok to access the code item here since JIT code will have been touched by the
          // interpreter and compiler already.
          uint16_t arg_offset = accessor.RegistersSize() - accessor.InsSize();
          ArtInterpreterToCompiledCodeBridge(self, nullptr, &shadow_frame, arg_offset, &result);
          // Push the shadow frame back as the caller will expect it.
          self->PushShadowFrame(&shadow_frame);
          return result;}}}} ... }


//   art/runtime/jit/jit.cc
//   Jit::MethodEntered()
void Jit::MethodEntered(Thread* thread, ArtMethod* method) {
...
      JitCompileTask compile_task(method, JitCompileTask::TaskKind::kCompile);
      // Fake being in a runtime thread so that class-load behavior will be the same as normal jit.
      ScopedSetRuntimeThread ssrt(thread);
      compile_task.Run(thread);
...
  if ((profiling_info != nullptr) &&
      (profiling_info->GetSavedEntryPoint() != nullptr) &&
      (method->GetEntryPointFromQuickCompiledCode() != GetQuickInstrumentationEntryPoint())) {
    Runtime::Current()->GetInstrumentation()->UpdateMethodsCode(
        method, profiling_info->GetSavedEntryPoint());
  } else {
    AddSamples(thread, method, 1, /* with_backedges= */false);
  }
}


// jit.cc
// Jit::CompileMethod
bool Jit::CompileMethod(ArtMethod* method, Thread* self, bool baseline, bool osr) {
...
  bool success = jit_compile_method_(jit_compiler_handle_, method_to_compile, self, baseline, osr);
...
  return success;
}


//  jit_compiler.cc
//  jit_compile_method
extern "C" bool jit_compile_method(
    void* handle, ArtMethod* method, Thread* self, bool baseline, bool osr)
    REQUIRES_SHARED(Locks::mutator_lock_) {
  auto* jit_compiler = reinterpret_cast<JitCompiler*>(handle);
  DCHECK(jit_compiler != nullptr);
  return jit_compiler->CompileMethod(self, method, baseline, osr);
}

//  JitCompiler::CompileMethod
bool JitCompiler::CompileMethod(Thread* self, ArtMethod* method, bool baseline, bool osr) {
  SCOPED_TRACE << "JIT compiling " << method->PrettyMethod();
...
  // Do the compilation.
  bool success = false;
  {
    TimingLogger::ScopedTiming t2("Compiling", &logger);
    JitCodeCache* const code_cache = runtime->GetJit()->GetCodeCache();
    uint64_t start_ns = NanoTime();
    success = compiler_->JitCompile(self, code_cache, method, baseline, osr, jit_logger_.get());
    uint64_t duration_ns = NanoTime() - start_ns;
    VLOG(jit) << "Compilation of "
              << method->PrettyMethod()
              << " took "
              << PrettyDuration(duration_ns);
  }
...
  return success;
}


// JitCompiler::JitCompiler
// compiler_是std::unique_ptr<Compiler>类型
JitCompiler::JitCompiler() {
  compiler_options_.reset(new CompilerOptions());
  ParseCompilerOptions();
  compiler_.reset(
      Compiler::Create(*compiler_options_, /*storage=*/ nullptr, Compiler::kOptimizing));
}
```
