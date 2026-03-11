# Creating UML Filesystems

> **Source:** <https://user-mode-linux.sourceforge.net/old/fs_making.html>
> **Archived:** 2026-03-10

---

### Creating your own filesystems


Creating your own UML root filesystems is an alternative to
downloading them from this site, either because none of these are what
you want, or they are too large to comfortably grab.


This page decribes and links to a set of projects which provide UML
filesystem builders of various types. They all require media for the
distribution that you are going to use.


### Summary


| | [mkrootfs](http://www.stearns.org/mkrootfs/) | [UML Builder](http://umlbuilder.sourceforge.net/) | [gBootRoot](http://gbootroot.sourceforge.net/) | [rootstrap](http://http.us.debian.org/debian/pool/main/r/rootstrap/) |
| --- | --- | --- | --- | --- |
| Most suitable for | people wanting to build multiple filesystems | Beginners | Beginners/Developers | Debian users |
| Needs root/sudo | Yes | No | No | No |
| Command line | Yes | Yes | Yes | Yes |
| Graphical | No | Yes | Yes | No |
| Sets up networking | Yes | Yes | No * | No |
| Sets up X | Yes | Yes | No * | No |


### mkrootfs


This is a script that I originally wrote in order in create
filesystems from a particular version of RH media. It has since been
taken over by Bill Stearns, who has generalized and improved it
greatly. It can build bootable UML filesystems from a wide variety of
RH-based distributions. It has been used to produce essentially all
of the RH-based filesystems available from this site.


It is available 
[here](http://www.stearns.org/mkrootfs/) 
(and also see 
[http://www.stearns.org/mkrootfs/rootfs.html](http://www.stearns.org/mkrootfs/rootfs.html)). Grab mkrootfs, functions, and mkswapfs, and run mkrootfs.
It prompts you for the information you need and is reasonably
self-explanatory.


### gBootRoot


[gBootRoot](http://gbootroot.sourceforge.net/) is a fairly general GTK-based app for creating UML root
filesystems, plus filesystems and boot disks for physical machines.


It also uses UML in order to evade permissions problems with loopback
mounting filesystems so they can be populated.


* Its IDE design allows boot and root creation methods to be added via
plugins, and some methods may be further enhanced via add-ons. Because of
this mechanism additional user-friendly features for filesystems like the
automation of X or Networking exist for some root methods.


### UML Builder


[umlbuilder](http://umlbuilder.sourceforge.net/) is a nice step-by-step UML filesystem builder. It comes in
command-line and GUI variants. Not only does it let you create a
filesystem, it sets up an rc script that runs UML with the
configuration that you specified and lets you control it from the host.


### rootstrap


This is a new tool by Matt Zimmerman for producing Debian UML
filesystem images. It is a work in progress, so some of the 'no's in
the table will change at some point. It's designed to produce Debian
images quickly with one command. It has a simple config file and
looks to be fairly easy to extend.
