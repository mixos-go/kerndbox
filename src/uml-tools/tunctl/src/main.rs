// SPDX-License-Identifier: GPL-2.0
//! tunctl — TUN/TAP device manager
//!
//! Usage:
//!   tunctl -t <dev> [-u <uid>]   create persistent TAP
//!   tunctl -d <dev>              delete TAP

use std::env;
use std::ffi::CString;
use std::fs;
use std::io;
use std::os::unix::io::IntoRawFd;

const TUNSETIFF:     libc::c_ulong = 0x400454ca;
const TUNSETOWNER:   libc::c_ulong = 0x400454cc;
const TUNSETPERSIST: libc::c_ulong = 0x400454cb;
const IFF_TAP:       libc::c_short = 0x0002;
const IFF_NO_PI:     libc::c_short = 0x1000;

#[repr(C)]
struct Ifreq {
    ifr_name:  [libc::c_char; libc::IF_NAMESIZE],
    ifr_flags: libc::c_short,
    _pad:      [u8; 22],
}

fn tun_open(dev: &str) -> io::Result<libc::c_int> {
    let fd = fs::OpenOptions::new().read(true).write(true)
        .open("/dev/net/tun")?.into_raw_fd();
    let mut ifr = Ifreq {
        ifr_name:  [0; libc::IF_NAMESIZE],
        ifr_flags: IFF_TAP | IFF_NO_PI,
        _pad:      [0; 22],
    };
    for (i, b) in dev.bytes().take(libc::IF_NAMESIZE - 1).enumerate() {
        ifr.ifr_name[i] = b as libc::c_char;
    }
    if unsafe { libc::ioctl(fd, TUNSETIFF, &ifr) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(fd)
}

fn lookup_uid(s: &str) -> libc::uid_t {
    if let Ok(n) = s.parse::<u32>() { return n; }
    let name = CString::new(s).unwrap();
    let pw = unsafe { libc::getpwnam(name.as_ptr()) };
    if !pw.is_null() { return unsafe { (*pw).pw_uid }; }
    eprintln!("tunctl: unknown user '{}', using current uid", s);
    unsafe { libc::getuid() }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut dev: Option<String> = None;
    let mut del = false;
    let mut owner = unsafe { libc::getuid() };
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-t" => { i += 1; dev = Some(args[i].clone()); del = false; }
            "-d" => { i += 1; dev = Some(args[i].clone()); del = true; }
            "-u" => { i += 1; owner = lookup_uid(&args[i]); }
            _    => {}
        }
        i += 1;
    }
    let dev = dev.unwrap_or_else(|| {
        eprintln!("Usage: tunctl -t <dev> [-u uid] | -d <dev>");
        std::process::exit(1);
    });
    let fd = tun_open(&dev).unwrap_or_else(|e| {
        eprintln!("tunctl: {}", e); std::process::exit(1);
    });
    if del {
        if unsafe { libc::ioctl(fd, TUNSETPERSIST, 0u64) } < 0 {
            eprintln!("TUNSETPERSIST 0: {}", io::Error::last_os_error());
        } else {
            println!("Set '{}' nonpersistent", dev);
        }
    } else {
        if unsafe { libc::ioctl(fd, TUNSETOWNER, owner as u64) } < 0 {
            eprintln!("TUNSETOWNER: {}", io::Error::last_os_error());
        }
        if unsafe { libc::ioctl(fd, TUNSETPERSIST, 1u64) } < 0 {
            eprintln!("TUNSETPERSIST 1: {}", io::Error::last_os_error());
        } else {
            println!("Set '{}' persistent and owned by uid {}", dev, owner);
        }
    }
    unsafe { libc::close(fd) };
}
