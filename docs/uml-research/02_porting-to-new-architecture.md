# Porting UML to a New Architecture

> **Source:** <https://user-mode-linux.sourceforge.net/old/arch-port.html>
> **Archived:** 2026-03-10

---

### Porting UML to a new architecture


Even though UML is running on a host Linux, which insulates it from
the underlying platform to a great extent, some details of the hardware
still leak through and make porting UML to Linux on a new architecture
more than a simple rebuild.


The major aspects of the hardware that show through are


- register names used by ptrace

- organization of the process address space


This page will describe how to port UML to a new architecture. It
will acquire new material as we learn more about how to do it. At
this point, this is based on what we learned from the ppc port, which
is the only real port of UML that's been done so far. The i386 port
doesn't really count since that was part of the overall development of
UML rather than a separate porting effort.


Below, there are references to $(SUBARCH). This is the make variable
which holds the value of the host architecture in the UML build. On
Intel boxes, it's "i386" and on PowerPC boxes, it's "ppc".

### Overview


UML is split between architecture-independent code and headers which
are found under arch/um in 


- kernel

- drivers

- fs

- ptproxy

- include


and the architecture-dependent code and definitions under arch/um in


- Makefile-*

- sys-*

- include/sysdep-*


Each '*' is the name of an architecture, so the i386-specific code is
under arch/um/sys-i386 and the ppc-specific code is under arch/um/sys-ppc.


### The host


Not all architectures can currently run UML. The potential problem is
the ability of ptrace to change system call numbers. i386 couldn't
until I got the change into 2.3.22 and 2.2.15, ppc could, and IA64 and
mips can't. I don't know about the other arches.


This is necessary because it's critical to UML's ability to virtualize
system calls. Process system calls must be nullified in the host, and
this is done by converting them into getpid.


So, before starting to work on your new port of UML, make sure ptrace
is fully functional. [This 
little program](https://user-mode-linux.sourceforge.net/old/examples/ptrace_test.c) starts a child, which makes calls to getpid and
prints them out, while the parent is converting the getpid calls to
getppid. The parent prints out its own pid, while the child prints out
what it thinks is its own pid, and they should be the same. So, if
your machine is able to run UML, you will see output like this:


```


Parent pid = 3246
getpid() returned 3246
getpid() returned 3246
```


If not, you will likely get errors from ptrace. Less likely is
different pids being printed out from the two processes. If either
happens, then you need to figure out how to remove that restriction
from the host Linux.


Note that when you compile ptrace.c, you will need to change the
references to ORIG_EAX, which contains the system call number, to
whatever is appropriate for your architecture.


### Address space layout


Before delving into the code, you need to do some high-level
conceptual thinking about how to organize the address space of a UML
process. UML maps its executable, physical memory, and kernel virtual
memory into the address space of each of its processes. You need to
decide where to put each of these so as to minimize the likelihood of
a process trying to allocate that memory for its own use.


The only arch hook at this point is where in the address space the UML
binary is going to load. The other addresses are still hard-coded
because they happen to work for both i386 and ppc. UML puts its own
memory in the area starting at 0x5000000 and process stacks 4M below
its own process stack. These choices may not work on all
architectures, so feel free to generalize them. To locate a likely
area on your arch, staring at /proc/<pid>/maps of various processes
on the host has been the technique so far.


### Architecture Makefile


You need to create arch/um/Makefile-$(SUBARCH), which contains the
following definitions:


- START_ADDR - The address where the UML executable will load in memory. This address must be chosen so that it won't conflict with any memory that a UML process is going to want to use. The i386 definition is ``` START_ADDR = 0x10000000 ```

- ARCH_CFLAGS - Anything that needs to be added to CFLAGS goes here. Both the i386 and ppc ports use this to turn off definitions that would pull hardware-specific code into the kernel. The ppc definition is ``` ARCH_CFLAGS = -U__powerpc__ -D__UM_PPC__ ```

- ELF_SUBARCH - This is the name of the ELF object format for the architecture. On i386, it's 'i386', but on ppc, it's not 'ppc' (it's 'powerpc'). The i386 definition is ``` ELF_SUBARCH = $(SUBARCH) ```


### include/asm-um


Every architecture needs to provide a set of headers to the generic
kernel. These are located in include/asm-$(ARCH). UML mostly uses
the headers of the underlying architecture. It does this by creating
a symlink from include/asm-um/arch to include/asm-$(SUBARCH). Most of
UML's headers then just include "asm/arch/header.h". As an example,
this is rwlock.h


```


#ifndef __UM_RWLOCK_H
#define __UM_RWLOCK_H

#include "asm/arch/rwlock.h"

#endif
```


Almost all of UML's headers look exactly like that. Some of the rest
are architecture-independent headers private to UML. You don't need to
worry about these.


Some headers include the underlying arch headers, but also need to
change them in some way. For example, the UML ptrace-generic.h includes
asm/arch/ptrace.h because it needs some definitions from there.
However, there are things it doesn't want because it needs to define
its own, such as struct pt_regs. So, the underlying architecture's
struct pt_regs is renamed by doing the following


```


#define pt_regs pt_regs_subarch
#include "asm/arch/ptrace.h"
#undef pt_regs
```


This changes the name of the underlying architecture's pt_regs to
struct pt_regs_subarch, allowing UML to define its own struct
pt_regs. This practice of taking most of the contents other
architecture's header and defining the unwanted bits away is useful,
but it also causes problems which porter have to deal with. For
example, the ppc ptrace.h includes "asm/system.h", which includes the
UML system.h. Since the UML system.h contains references to pt_regs
and it's being included by a header that has had pt_regs renamed to
pt_regs_subarch, the UML system.h references are similarly renamed.
This causes conflicts against files which expect references to
pt_regs. There have been several attempts to update UML/ppc and this
problem has stymied them. It's far from an insolvable problem, but it
involves staring at confusing sequences of includes, figuring out
what's happening, and how to fix it.


There are also a few headers which are archtecture-dependent.


- archparam-$(SUBARCH).h **This is a header for miscellaneous architecture-dependent definitions. In a lot of cases, a mostly-generic header can get its non-generic definitions from a separate header. In these cases, the definitions are put in archparam-$(SUBARCH).h and that header includes asm/archparam.h, which is a symbolic link to archparam-$(SUBARCH).h. The i386 archparam mostly includes definitions for elf.h, such as platform-specific register initializatins. The ppc archparam is similar, adding a couple of definitions for hardirq.h and a couple of other headers. processor-$(SUBARCH).h This header exists because UML/ppc needs a little logic to choose between including one header and another. ptrace-$(SUBARCH).h This defines architecture-dependent access macros into struct pt_regs. These macros aren't used in generic code, but you may need some when you define ELF_PLAT_INIT and a few other things. Those definitions should go here. sigcontext-$(SUBARCH).h This is similar to processor-$(SUBARCH).h. It exists so that that the occurrences of pt_regs in asm-$(SUBARCH)/sigcontext.h can be defined out of the way. system-$(SUBARCH).h This header exists so that UML/ppc can define the ppc _switch_to out of the way. The i386 version doesn't do anything. ptrace-generic.h ptrace-generic.h isn't architecture-dependent, but it does put some requirements on arch/um/include/sysdep/ptrace.h, which you will meet below. It defines its struct pt_regs as ``` struct pt_regs { struct uml_pt_regs regs; }; ``` and it's up to the architecture to define struct uml_pt_regs. This is done this way because some UML userspace code needs to refer to register values. So, uml_pt_regs is the structure that is safe for userspace code to look at, which pt_regs is for kernel code. Access macros for pt_regs therefore just call the equivalent access macro for uml_pt_regs, like ``` #define PT_REGS_IP(r) UPT_IP(&(r)->regs) ``` and these should be defined in arch/um/include/sysdep/ptrace.h, which should be able to be included in both user and kernel code. This means it can't include either libc headers or kernel headers, but may include safe UML headers. ### Architecture headers There are three headers, which go in arch/um/include/sysdep-$(SUBARCH), which need to be written, and each needs to contain a certain set of definitions. frame.h** One of the first things that UML does when it boots is it creates and saves a signal frame. This will be used when it delivers signals to its processes. It will be copied onto the process stack and the data in the original frame, like the signal number, sigcontext contents, and restorer will be replaced. UML knows how to replace this stuff because it figured out where in the stack frame it is. And it did that by having the signal handler record the address of the signal, the sigcontext structure, and a few other things. This is done in a mostly architecture-independent way, but a little help is needed from architecture-specific code. That code goes into frame.h. What's needed here are definitions of: ``` static inline unsigned long frame_restorer(void) ``` This returns the location on the stack of the signal state restorer. On i386, this is the return address, which is next to the frame pointer, so the i386 definition is ``` static inline unsigned long frame_restorer(void) { unsigned long *fp; fp = __builtin_frame_address(0); return((unsigned long) (fp + 1)); } ``` ``` static inline unsigned long frame_sp(void) ``` This returns the value of the stack pointer when the signal handler is first entered. Note that this is not necessarily the same value as when the signal handler code is executing because it may have been adjusted for local variables. On i386, this is four bytes more than the frame pointer, so its definition is ``` static inline unsigned long frame_sp(void) { unsigned long *fp; fp = __builtin_frame_address(0); return((unsigned long) (fp + 1)); } ``` In addition, there may be a need for the architecture to save more information from the signal frame. There are two pairs of structures and procedures which allow you to do this. The first pair are expected to record raw addresses from the frame: ``` struct arch_frame_data_raw { ... }; static inline void setup_arch_frame_raw(struct arch_frame_data_raw *data, struct sigcontext *sc) ``` The arch_frame_data_raw may contain anything you want and setup_arch_frame_raw is expected to fill it in. Both may be empty. i386 needs to know the size of the floating point state that's on the signal frame, so these save the address of the beginning of the sigcontext structure, where the floating point state ends: ``` struct arch_frame_data_raw { unsigned long sc_end; }; static inline void setup_arch_frame_raw(struct arch_frame_data_raw *data, struct sigcontext *sc) { data->sc_end = (unsigned long) sc; data->sc_end += sizeof(*sc); } ``` Then a similar structure and function pair is used to process the raw addresses into something that's usable later. The i386 code assumes that the floating point state runs from the top of the stack (which is alone on its own page, so the top of the stack is the end of the page) to the start of the sigcontext structure: ``` struct arch_frame_data { int fpstate_size; }; static inline void setup_arch_frame(struct arch_frame_data_raw *in, struct arch_frame_data *out) { unsigned long fpstate_start = in->sc_end; fpstate_start &= ~PAGE_MASK; out->fpstate_size = PAGE_SIZE - fpstate_start; } ``` **ptrace.h** ptrace.h deals with the machine's register set. It defines the following: ``` struct uml_pt_regs ``` which should contain a system call number, a set of system call arguments, a flag saying whether the kernel was entered from userspace or kernelspace, and a pointer to the sigcontext structure on the current stack. The i386 definition is ``` struct uml_pt_regs { unsigned long args[6]; long syscall; int is_user; void *sc; }; ``` which may in fact be architecture-independent. The only thing that may need changing is the size of args[]. ``` EMPTY_UML_PT_REGS ``` which is an initializer for uml_pt_regs. The i386 definition is ``` #define EMPTY_UML_PT_REGS { \ syscall : -1, \ args : { [0 ... 5] = 0 }, \ is_user : 0, \ sc : NULL } ``` ``` UPT_REG(regs, reg) ``` which returns the value of the appropriate register from the saved sigcontext. ``` UPT_SET(regs, reg, val) ``` which sets the value of the appropriate register in the saved sigcontext to whatever value is passed in. The i386 definitions of these are big switch statements ``` #define UPT_REG(regs, reg) \ ({ unsigned long val; \ switch(reg){ \ case EIP: val = UPT_IP(regs); break; \ case UESP: val = UPT_SP(regs); break; \ case EAX: val = UPT_EAX(regs); break; \ case EBX: val = UPT_EBX(regs); break; \ case ECX: val = UPT_ECX(regs); break; \ case EDX: val = UPT_EDX(regs); break; \ case ESI: val = UPT_ESI(regs); break; \ case EDI: val = UPT_EDI(regs); break; \ case EBP: val = UPT_EBP(regs); break; \ case ORIG_EAX: val = UPT_ORIG_EAX(regs); break; \ case CS: val = UPT_CS(regs); break; \ case SS: val = UPT_SS(regs); break; \ case DS: val = UPT_DS(regs); break; \ case ES: val = UPT_ES(regs); break; \ case FS: val = UPT_FS(regs); break; \ case GS: val = UPT_GS(regs); break; \ case EFL: val = UPT_EFLAGS(regs); break; \ default : \ panic("Bad register in UPT_REG : %d\n", reg); \ val = -1; \ } \ val; \ }) #define UPT_SET(regs, reg, val) \ do { \ switch(reg){ \ case EIP: UPT_IP(regs) = val; break; \ case UESP: UPT_SP(regs) = val; break; \ case EAX: UPT_EAX(regs) = val; break; \ case EBX: UPT_EBX(regs) = val; break; \ case ECX: UPT_ECX(regs) = val; break; \ case EDX: UPT_EDX(regs) = val; break; \ case ESI: UPT_ESI(regs) = val; break; \ case EDI: UPT_EDI(regs) = val; break; \ case EBP: UPT_EBP(regs) = val; break; \ case ORIG_EAX: UPT_ORIG_EAX(regs) = val; break; \ case CS: UPT_CS(regs) = val; break; \ case SS: UPT_SS(regs) = val; break; \ case DS: UPT_DS(regs) = val; break; \ case ES: UPT_ES(regs) = val; break; \ case FS: UPT_FS(regs) = val; break; \ case GS: UPT_GS(regs) = val; break; \ case EFL: UPT_EFLAGS(regs) = val; break; \ default : \ panic("Bad register in UPT_SET : %d\n", reg); \ break; \ } \ } while (0) ``` In addition to whatever macros you call from any additional PT_REGS_* macros you define, there are a few that you definitely need equivalents to. These will generally call into sigcontext macros since they need to modify the current sigcontext. UPT_SET_SYSCALL_RETURN **This sets the system call return value UPT_RESTART_SYSCALL This does whatever is necessary to make sure that the current system call will restart when userspace is entered. Backing up the IP so that it points at the system call instruction is probably enough. UPT_ORIG_SYSCALL This is the original location of the system call number. i386 moves it from EAX to ORIG_EAX, so it refers to EAX. This is used when restarting a system call to restore the registers to their original values. UPT_SYSCALL_NR This pulls the system call number from the uml_pt_regs. On i386, it comes directly from the uml_pt_regs structure. On other architectures, it may make sense to get it from the sigcontext. UPT_SYSCALL_RET This returns the system call return value. ptrace_user.h** This file defines a set of access macros into the hosts's pt_regs structure. This is purely a userspace file which is used by parts of UML which use ptrace to pull the process registers from the host kernel and need to interpret them. These are the definitions that should be here, and they should be implemented in terms of register definitions in the host <asm/ptrace.h>. PT_SYSCALL_NR

- PT_SYSCALL_NR_OFFSET **The pt_regs index and ptrace offset of the system call number PT_SYSCALL_ARG1_OFFSET PT_SYSCALL_ARG2_OFFSET PT_SYSCALL_ARG3_OFFSET PT_SYSCALL_ARG4_OFFSET PT_SYSCALL_ARG5_OFFSET The offsets of the system call arguments PT_SYSCALL_RET_OFFSET The offset of the system call return value PT_IP PT_IP_OFFSET The pt_regs index and offset of the IP PT_SP The index of the stack pointer FRAME_SIZE FRAME_SIZE_OFFSET If the host pt_regs doesn't define FRAME_SIZE, set it to the number of general purpose registers. Set FRAME_SIZE_OFFSET to the maximum offset for PTRACE_GETREGS. FP_FRAME_SIZE FPX_FRAME_SIZE These are the number of floating point registers and extended floating point registers, respectively. The second is likely x86-specific. If you don't define UM_HAVE_GETFPREGS/UM_HAVE_SETFPREGS or UM_HAVE_GETFPXREGS/UM_HAVE_SETFPXREGS (see below), you can leave the corresponding _FRAME_SIZE undefined. UM_HAVE_GETREGS UM_HAVE_SETREGS UM_HAVE_GETFPREGS UM_HAVE_SETFPREGS UM_HAVE_GETFPXREGS UM_HAVE_SETFPXREGS These should be defined if the architecture defines PTRACE_GETREGS, PTRACE_SETREGS, PTRACE_GETFPREGS, PTRACE_SETFPREGS, PTRACE_GETFPXREGS, PTRACE_,SETFPXREGS respectively. sigcontext.h** sigcontext.h defines a few sigcontext-related macros. Some of them are accessed through the PT_REGS and UPT_REGS macros, so their details are up to you. You will have to define similar things at the very least, so here's what i386 defines SC_RESTART_SYSCALL **Does whatever IP fiddling is needed to cause the current system call to restart when userspace is re-entered. On i386, this just subtracts 2 from the IP since a system call instruction is 2 bytes long. SC_SET_SYSCALL_RETURN Sets the system call return value. On i386, this just sets %eax. On ppc, it does a little more than that. SC_FAULT_ADDR SC_FAULT_WRITE These two are called from generic UML code, so you have to implement these as described. On a segfault, they pick out from a sigcontext the fault address and whether the fault was on a write. SEGV_IS_FIXABLE This evaluates to non-zero if a segfault is one that can be fixed by mapping in a page or changing page protections. If not, then it returns zero, and the faulting process will simply be segfaulted. This is called from generic UML code. SC_START_SYSCALL This is a general hook that's called at the start of a system call before ptrace gets to see it. On x86, strace expects %eax to contain -ENOSYS when it sees a system call entry. So, this macro sets that. On other architectures, this may do nothing. This is called from generic UML code. void sc_to_regs(struct uml_pt_regs *regs, struct sigcontext *sc, unsigned long syscall) This is called at the beginning of a system call to fill in a pt_regs structure from the sigcontext. It parses the system call from the sigcontext and fills in the system call number and the arguments in the pt_regs. This is called from generic UML code. syscalls.h** syscalls.h defines any architecture-specific system calls. It does so by defining ARCH_SYSCALLS **which is a set of array element initializers which will be included in the initialization of the system call table. The i386 ARCH_SYSCALLS looks in part like this ``` #define ARCH_SYSCALLS \ [ __NR_mmap ] = old_mmap_i386, \ [ __NR_select ] = old_select, \ [ __NR_vm86old ] = sys_ni_syscall, \ [ __NR_modify_ldt ] = sys_modify_ldt, \ ... [ 222 ] = sys_ni_syscall, ``` Also, you must define LAST_ARCH_SYSCALL to be the last initialized element defined by ARCH_SYSCALLS. This is used to fill the end of the system call table properly. In addition, syscalls.h defines EXECUTE_SYSCALL(syscall, regs) which calls into a system call entry. The i386 pt_regs has been arranged so that it can just be dumped on the stack and the right thing will happen ``` #define EXECUTE_SYSCALL(syscall, regs) (*sys_call_table[syscall])(*regs); ``` ### Port implementation The actual implementation of the port is contained in sys-$(SUBARCH). You have complete freedom in this directory, except that when it is built, it must produce an object file named sys.o which contains all the code required by the generic kernel. Here is a list of the files used by the existing ports, along with what they define. ptrace.c** ``` int putreg(struct task_struct *child, unsigned long regno, unsigned long value) ``` This does any needed validity checking on the register and the value, and assigns the value to the appropriate register in child->thread.process_regs. If it fails, it returns -EIO. This may be changed in the future so that it is provided with just the register set rather than the whole task structure. ``` unsigned long getreg(struct task_struct *child, unsigned long regno) ``` getreg fetches the value of the requested register from child->thread.process_regs, doing any required masking of registers which don't use all their bits. This may also be changed to take the register set rather than the task structure. **ptrace_user.c** Linux doesn't implement PTRACE_SETREGS and PTRACE_GETREGS on all architectures. This file contains definitions of ptrace_getregs and ptrace_setregs to hide this difference from the generic code. Architectures which define PTRACE_SETREGS and PTRACE_GETREGS will implement these functions as follows ``` int ptrace_getregs(long pid, struct sys_pt_regs *regs_out) { return(ptrace(PTRACE_GETREGS, pid, 0, regs_out)); } int ptrace_setregs(long pid, struct sys_pt_regs *regs) { return(ptrace(PTRACE_SETREGS, pid, 0, regs)); } ``` Architectures which don't will implement them as loops which call ptrace(PTRACE_GETREG, ...) or ptrace(PTRACE_SETREG, ...) for each register. **semaphore.c** This implements the architecture's semaphore primitives. It is highly recommended to steal this from the underlying architecture by having the Makefile make a link from arch/$(SUBARCH)/kernel/semaphore.c to arch/um/sys-$(SUBARCH)/semaphore.c. **checksum.c or checksum.S** This implements the architecture's ip checksumming. This is stolen from the underlying architecture in the same manner as semaphore.c. **sigcontext.c** This defines a few sigcontext-related functions int sc_size(void *data) **How big is a sigcontext? On x86, this takes the floating point state into account as well as just the sigcontext structure itself. int copy_sc_to_user(void *to_ptr, void *from_ptr, void *data) Copies a sigcontext to a process stack. It must use copy_to_user, not memcopy. int copy_sc_from_user(void *to_ptr, void *from_ptr, void *data) Copies a sigcontext from a process stack into kernel memory. Similarly, this must use copy_from_user, not memcopy. void sc_to_sc(void *to_ptr, void *from_ptr) This copies a sigcontext from one kernel stack to another. It is used during thread creation (kernel_thread(), fork(), or clone()) to initialize a kernel stack with a signal frame that the new process can return from. sysrq.c** This needs to define void show_regs(struct pt_regs *regs) **For the benefit of the SysRq driver. Other files** If Linux on your architecture defines any private system calls, you will need to implement them here. Normally, you can take the code from the underlying architecture, and you might get away with linking to the files in the other architecture that implement them. ### Debugging the new port There's no algorithm for doing this stage of the port, so I'll just describe a number of useful tricks. gdb is available. Use it. It's usable for any part of the kernel after the beginning of start_kernel. If you need to debug anything before that, the 'debugtrace' option is handle. It causes the tracing thread to stop and wait to be attached with gdb. Then you can step through the very early boot before start_kernel. If you're post-mortem-ing a bug and you want to see what just happened inside UML, there are some arrays which store some useful recent history: signal_record - stores the last 1024 signals seen by the tracing thread, including the host pid of the process getting the signal, the time, and the IP at which the signal happened. This is a circular buffer and the latest entry is at index signal_index - 1.

- syscall_record - the same, except it stores process system calls. It stores the system call number, the return value (and 0xdeadbeef is stored there if it hasn't returned), the UML pid of the process, and the time. It is indexed by syscall_index, so the most recent entry is at index syscall_index - 1.


These provide a decent picture of what UML has been doing lately.
Looking for unusual things here immediately before a bug happened is a
useful debugging technique. Correlating timestamps between the two
arrays is also sometimes useful.


If you have reproducable memory corruption, an extremely useful way to
track it down is to set the page that it happens on read-only and to
see what seg faults when it tries writing to that page. Obviously,
this only works if there aren't legitimate writes happening to that
page at the same time.
