# UML Kernel — Compiling & Command-Line Switches

> **Sources (merged)**
> - <https://user-mode-linux.sourceforge.net/old/compile.html>
> - <https://user-mode-linux.sourceforge.net/old/switches.html>
>
> **Archived:** 2026-03-10
>
> **Why merged:** These two pages are tightly coupled — `compile.html`
> explains how to build the UML kernel, and `switches.html` documents
> all the kernel command-line parameters used at runtime.
> Together they form a complete "build and configure" reference.

---

## Part 1 — Compiling the Kernel and Modules

_Source: <https://user-mode-linux.sourceforge.net/old/compile.html>_

### Compiling the kernel and modules


### Compiling the kernel


Compiling the user mode kernel is just like compiling any other
kernel. Let's go through the steps, using 2.4.0-prerelease (current
as of this writing) as an example:


- Download the latest UML patch from [the download page](https://user-mode-linux.sourceforge.net/old/dl-sf.html) In this example, the file is uml-patch-2.4.0-prerelease.bz2.


- Download the matching kernel from your favourite kernel mirror, such as: http://ftp.ca.kernel.org/linux/kernel/ [http://ftp.ca.kernel.org/linux/kernel/](http://ftp.ca.kernel.org/linux/kernel/).


- Make a directory and unpack the kernel into it. > > > host% > mkdir ~/uml > > > > > > host% > cd ~/uml > > > > > > host% > tar -xjvf linux-2.4.0-prerelease.tar.bz2 > > >


- Apply the patch using > > > host% > cd ~/uml/linux > > > > > > host% > bzcat uml-patch-2.4.0-prerelease.bz2 | patch -p1 > > >


- Run your favorite config; `make xconfig ARCH=um' is the most convenient. `make config ARCH=um' and 'make menuconfig ARCH=um' will work as well. The defaults will give you a useful kernel. If you want to change something, go ahead, it probably won't hurt anything. Note: If the host is configured with a 2G/2G address space split rather than the usual 3G/1G split, then the packaged UML binaries will not run. They will immediately segfault. See [this page](https://user-mode-linux.sourceforge.net/old/2G-2G.html) for the scoop on running UML on your system.


- Finish with `make linux ARCH=um': the result is a file called `linux' in the top directory of your source tree.
You may notice that the final binary is pretty large (many 10's of
megabytes for a debuggable UML). This is almost entirely symbol
information. The actual binary is comparable in size to a native
kernel. You can run that huge binary, and only the actual code and
data will be loaded into memory, so the symbols only consume disk
space unless you are running UML under gdb. You can strip UML:

> 
> 
> host% strip linux
> 
> 

to see the true size of the UML kernel.


Make sure that you don't build this
kernel in /usr/src/linux. On some distributions, /usr/include/asm
is a link into this pool. The user-mode build changes the other end
of that link, and things that include <asm/anything.h> stop compiling.

The sources are also available from cvs. You can [browse](http://www.user-mode-linux.org/cvs) the CVS pool
or access it anonymously via

> 
> 
> cvs -d:pserver:anonymous@www.user-mode-linux.org:/cvsroot/user-mode-linux
> _cvs command_
> 
> 
> 


If you get the CVS sources, you will have to check them out into an
empty directory. You will then have to copy each file into the corresponding
directory in the appropriate kernel pool.

If you don't have the latest kernel pool, you can get the corresponding
user-mode sources with 
> 
> 
> host% cvs co -r v_2_3_x linux
> 
> 

where 'x' is the version in your pool. Note that you will not get the bug
fixes and enhancements that have gone into subsequent releases.


If you build your own kernel, and want to boot it from one of the
filesystems distributed from this site, then, in nearly all cases,
devfs must be compiled into the kernel and mounted at boot time. The
exception is the tomsrtbt filesystem. For this,
devfs must either not be in the kernel at all, or "devfs=nomount" must
be on the kernel command line. Any disagreement between the kernel
and the filesystem being booted about whether devfs is being used will
result in the boot getting no further than single-user mode.


If you don't want to use devfs, you can remove the need for it from a
filesystem by copying /dev from someplace, making a bunch of
/dev/ubd devices:

> 
> 
> UML# 
> for i in 0 1 2 3 4 5 6 7; do mknod ubd$i b 98 $[ $i * 16 ]; done
> 
> 
> 

and changing /etc/fstab and /etc/inittab to refer to the non-devfs devices.


### Compiling and installing kernel modules


UML modules are built in the same way as the native kernel (with the
exception of the 'ARCH=um' that you always need for UML):

> 
> 
> host% make modules ARCH=um
> 
> 
> Any modules that you want to load into this kernel need to
> be built in the user-mode pool. Modules from the native kernel won't
> work. If you notice that the modules you get are much larger than
> they are on the host, see the note above about the size of the final
> UML binary.
> 
You can install them by using ftp or something to copy them into the
> virtual machine and dropping them into /lib/modules/`uname -r`.
> 
You can also get the kernel build process to install them as
> follows:
> 

> 
- > with the kernel not booted, mount the root filesystem in the top level > of the kernel pool: > > > host% mount root_fs mnt -o loop > >


- run > > > host% > make modules_install INSTALL_MOD_PATH=`pwd`/mnt ARCH=um > > >


- unmount the filesystem > > > host% umount mnt > >


- boot the kernel on it


If you can't mount the root filesystem on the host for some reason
(like it's a COW file), then an alternate approach is to mount the
UML kernel tree from the host into the UML with [hostfs](https://user-mode-linux.sourceforge.net/old/hostfs.html) and run the modules_install inside
UML:


- With UML booted, mount the host kernel tree inside UML at the same location as on the host: > > > UML# mount none -t hostfs _path to UML pool_ -o > _path to UML pool_ > > >

- Run make modules_install: > > > UML# cd _path to UML pool_ ; make modules_install > > >


The depmod at the end may complain about unresolved symbols because
there is an incorrect or missing System.map installed in the UML
filesystem. This appears to be harmless. insmod or modprobe should
work fine at this point.


When the system is booted, you can use insmod as usual to get the modules
into the kernel. A number of things have been loaded into UML as
modules, especially filesystems and network protocols and filters, so
most symbols which need to be exported probably already are. However,
if you do find symbols that need exporting, let [us](https://user-mode-linux.sourceforge.net/old/contacts.html) know, and they'll be "taken care of".


If you try building an external module against a UML tree, you will
find that it doesn't compile because of missing includes. There are
less obvious problems with the CFLAGS that the module Makefile or
script provides which would make it not run even if it did build. To
get around this, you need to provide the same CFLAGS that the UML
kernel build uses.


A reasonably slick way of getting the UML CFLAGS is

> 
> 
> 
> cd _uml-tree_ ; make script 'SCRIPT=@echo $(CFLAGS)' ARCH=um
> 
> 
> 

If the module build process has something that looks like

> 
> 
> $(CC) $(CFLAGS) _file_
> 
> 
> 

then you can define CFLAGS in a script like this

> 
> 
> 
> CFLAGS=`cd _uml-tree_ ; make script 'SCRIPT=@echo $(CFLAGS)' ARCH=um`
> 
> 
> 

and like this in a Makefile

> 
> 
> 
> CFLAGS=$(shell cd _uml-tree_ ; make script 'SCRIPT=@echo
> $$(CFLAGS)' ARCH=um)
> 
> 
> 


### Compiling and installing uml_utilities


Many features of the UML kernel require a user-space helper program, 
so a uml_utilities package is distributed separately from the kernel 
patch which provides these helpers. Included within this is:


- port-helper - Used by consoles which connect to xterms or ports

- tunctl - Configuration tool to create and delete tap devices

- uml_net - Setuid binary for automatic tap device configuration

- uml_switch - User-space virtual switch required for daemon transport


The uml_utilities tree is compiled with:

> 
> 
> host# 
> make && make install
> 
> 
> 
> Note that UML kernel patches may require a specific version of the 
> uml_utilities distribution. If you don't keep up with the mailing lists, 
> ensure that you have the latest release of uml_utilities if you are 
> experiencing problems with your UML kernel, particularly when dealing 
> with consoles or command-line switches to the helper programs
>

---

## Part 2 — Kernel Command-Line Switches

_Source: <https://user-mode-linux.sourceforge.net/old/switches.html>_

### Kernel command line switches


This is a list of the UML-specific command line arguments, plus a few
generic ones which deserve mention here.


### --help


This causes UML to print a usage message and exit.


### --version


This causes UML to print its version and exit.


### --showconfig


This causes UML to print the config file it was built with and exit.


### con


**con=channel** attaches one or more UML consoles to the
named channel. The format of the channel is described
[here](https://user-mode-linux.sourceforge.net/old/input.html).


### debug


Starts up the kernel under the control of gdb. See the 
[kernel debugging
tutorial](https://user-mode-linux.sourceforge.net/old/debugging.html) and the [debugging session](https://user-mode-linux.sourceforge.net/old/debug-session.html) pages for more information. Another form of
this switch is **debug=go** which is the same as **debug**
except that the kernel runs instead of stopping at the beginning of
start_kernel.


If you're using ddd to debug UML, you will want to specify
**debug=parent** as well as **gdb-pid** (see below).


This switch is specific to [tt
mode](https://user-mode-linux.sourceforge.net/old/skas.html) and has no effect in skas mode.


### debugtrace


Causes the tracing thread to pause until it is attached by a debugger
and continued. This is mostly for debugging crashes early during
boot, and should be pretty much obsoleted by the **debug** switch.


This switch is specific to [tt
mode](https://user-mode-linux.sourceforge.net/old/skas.html) and has no effect in skas mode.


### dsp


**dsp=host dsp** tells the UML sound driver what the
filename of the host dsp is so that it can relay to it. The default
is "/dev/sound/dsp".


### eth


**ethn=host interface** enables a virtual ethernet
device inside UML. See the
[networking HOWTO](https://user-mode-linux.sourceforge.net/old/networking.html)
for more information on setting up UML networking.


### fakehd


Causes the ubd device to put its partition information in
/proc/partitions under the device name "hd" rather than "ubd". Again,
this is to fake out installation procedures which are overly picky in
their sanity-checking.


### fake_ide


**fake_ide** causes the ubd driver to install realistic-looking
entries into /proc/ide. This is useful for convincing some
distribution installation procedures to run inside UML.


### gdb-pid


**gdb-pid=pid**, when used with **debug**, specifies the pid of
an already running debugger that UML should attach to. This can be used
to debug UML with a gdb wrapper such as emacs or ddd, as well as with debuggers
other than gdb. See the [debugging page](https://user-mode-linux.sourceforge.net/old/debugging.html) for more information.


This switch is specific to [tt
mode](https://user-mode-linux.sourceforge.net/old/skas.html) and has no effect in skas mode.


### honeypot


**honeypot** causes UML to rearrange its address space in order to
put process stacks in the same location as on the host. This allows
stack smash exploits to work against UML just as they do against the
host. This option enables **jail**, since it is most unlikely that
a honeypot UML should run without it enabled.


This switch is specific to [tt
mode](https://user-mode-linux.sourceforge.net/old/skas.html) and has no effect in skas mode. Honeypots should be run
in skas mode anyway, since they will perform far better, and the
security model is much simpler, making it less likely that there will
be exploitable bugs that will allow an attacker to break out.


### initrd


**initrd=image** sets the filename of the initrd image that
UML will boot from.


### iomem


**iomem=name,file** makes _file_ available to be
mapped by a driver inside UML. See 
[this page](https://user-mode-linux.sourceforge.net/old/iomem.html) for more information.


### jail


**jail** enables protection of UML kernel memory from UML
processes. This is disabled by default for performance reasons.
Without it, it is fairly simple to break out of UML by changing the
right pieces of UML kernel data.


This switch is specific to [tt
mode](https://user-mode-linux.sourceforge.net/old/skas.html) and has no effect in skas mode. skas mode doesn't have
the same problems with processes being able to break out to the host,
so this switch isn't needed. Effectively, 'jail' mode is always
enabled in skas mode.


### mconsole


**mconsole=notify:socket** asks the mconsole driver to send
the name of its socket to the Unix socket named by this switch. This
is intended for the use of scripts which want to know when they can
start using the mconsole and what socket they should send commands to.


### mem


**mem=size** controls how much "physical" memory the kernel 
allocates for the system. The size is specified as a number followed by one 
of 'k', 'K", 'm', 'M", which have the obvious meanings. This is not related
to the amount of memory in the physical machine. It can be more, and
the excess, if it's ever used, will just be swapped out.


In its default configuration, UML has a maximum physical memory size
of just under 512M. If you specify more than that, it will be shrunk,
and a warning printed out. If your UML is configured with highmem
support (CONFIG_HIGHMEM) enabled, then any physical memory beyond what
can be directly mapped in to the kernel address space will become
highmem. In this case, the current limit on UML physical memory is 4G.


Something to note if you have a small /tmp is that UML creates a file
in /tmp which is the same size as the memory you specified. It is not
visible because UML unlinks it after creating it. This can cause /tmp
to mysteriously become full. UML respects the TMP, TEMP, and TMPDIR
environment variables, so you can avoid this problem by specifying an
alternate temp directory.


Something else to note is that UML is noticably faster with a tmpfs
/tmp than with a disk-based /tmp such as ext2 or ext3.


### mixer


**mixer=host mixer** tells the UML sound driver what the
filename of the host mixer is so that it can relay to it. The default
is "/dev/sound/mixer".


### mode=tt


**mode=tt** forces UML to run in tt mode (see 
[this page](https://user-mode-linux.sourceforge.net/old/skas.html) for the
details) even when skas support is built in to UML and the host.
Using this switch without both tt and skas modes built in to UML will
have no effect aside from producing a warning during boot.


### ncpus


**ncpus=number** tells an SMP kernel how many virtual processors to 
start. This switch will only take effect if CONFIG_UML_SMP is enabled
in the UML configuration.


### ssl


**ssl=channel** attaches one or more UML serial lines to the
named channel. The format of the channel is described
[here](https://user-mode-linux.sourceforge.net/old/input.html).


### root


**root=root device** is actually used by the generic kernel in 
exactly the same way as in any other kernel. If you configure a number of 
block devices and want to boot off something other than ubd0, you would use something like:

> 
> 
> root=/dev/ubd5
> 
> 
> 


### tty_log_dir


**tty_log_dir=directory** changes the directory to which UML
writes tty logging files. This requires that tty logging be
configured into UML. See the 
[tty logging page](https://user-mode-linux.sourceforge.net/old/tty_logging.html)
for more details.


### tty_log_fd


**tty_log_fd=file descriptor** causes tty logging records to
be written to the file descriptor specified. This descriptor must be
opened before UML is run and passed in to UML. See the 
[tty logging page](https://user-mode-linux.sourceforge.net/old/tty_logging.html) 
for more details.


### ubd


**ubd=number** causes the ubd device to take over a different major 
number than the one assigned to it. This is useful for making it appear to 
be an "hd" device.


### ubd


**ubdn=filename** is used to associate a device with a file 
in the underlying filesystem. Usually, there is a filesystem in the file, 
but that's not required. Swap devices containing swap files can be specified
like this. Also, a file which doesn't contain a filesystem can have
its contents read in the virtual machine by running dd on the device.
n must be in the range 0 to 7. Appending an 'r' to the number will
cause that device to be mounted read-only. Appending an 's' will
cause that device to do all IO to the host synchronously. If both 'r'
and 's' are specified, it must be as 'rs'.


Inside UML, if you are not using devfs, the devices are accessible
with minor numbers 0, 16, ..., with the other minor numbers being used
for partitions. So, the device that is ubd1 on the UML command line
becomes /dev/ubd16 inside UML.


### ubd


**ubdn=cow-file,backing-file** is used to layer a COW
file on another, possibly readonly, file. This is useful in a number
of ways. See [this
page](https://user-mode-linux.sourceforge.net/old/shared_fs.html) for all the details.


### umid


**umid=name** is used to assign a name to a virtual machine. This
is intended to make it easy for UIs to manage multiple UMLs. Currently, the
only effect of this is that UML writes its tracing thread pid in 
/tmp/uml/_name_.


### uml_dir


**uml_dir=directory** sets the directory in which UML will
put the umid directory, which in turn will contain the pid file and
mconsole socket.


### umn


**umn=ip-address** sets the ip address of the host side of the slip 
device that the umn device configures. This is necessary if you want to set up
networking, but your local net isn't 192.168.0.x, or you want to run
multiple virtual machines on a network, in which case, you need to
assign different ip addresses to the different machines. See the 
[networking tutorial](https://user-mode-linux.sourceforge.net/old/networking.html) for more information.


### xterm


**xterm=terminal emulator,title switch,exec
switch** allows you to specify an alternate terminal emulator for
UML to use for the debugger, consoles, and serial lines. _terminal
emulator_ is the emulator itself, _title switch_ is the switch
it uses to set its title, and _exec switch_ is the switch it uses
to specify a command line to exec. The two switches need to have the
same syntax and semantics of xterm's "-T" and "-e". The default
value is "xterm=xterm,-T,-e". To use gnome-terminal, you would
specify "xterm=gnome-terminal,-t,-x". If any fields are left blank,
the default values will be used. So, to use "myxterm", which has the
same switches as xterm, "xterm=myxterm" will suffice.
