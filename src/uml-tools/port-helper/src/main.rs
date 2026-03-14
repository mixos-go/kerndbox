// SPDX-License-Identifier: GPL-2.0
//! port-helper — UML console bridge
//!
//! Mode 1 (port): stdin/stdout ↔ kernel pipe fd (UML_PORT_HELPER_FD env)
//! Mode 2 (xterm): terminal ↔ Unix domain socket (-uml-socket <path>)

use std::env;
use std::os::unix::net::UnixStream;
use std::os::unix::io::{AsRawFd, RawFd};

fn bridge(a: RawFd, b: RawFd) {
    let mut buf = [0u8; 4096];
    loop {
        let mut rfds = unsafe { std::mem::zeroed::<libc::fd_set>() };
        unsafe {
            libc::FD_ZERO(&mut rfds);
            libc::FD_SET(a, &mut rfds);
            libc::FD_SET(b, &mut rfds);
        }
        let max = a.max(b) + 1;
        let r = unsafe {
            libc::select(max, &mut rfds, std::ptr::null_mut(),
                         std::ptr::null_mut(), std::ptr::null_mut())
        };
        if r < 0 {
            if unsafe { *libc::__errno_location() } == libc::EINTR { continue; }
            break;
        }

        let a_ready = unsafe { libc::FD_ISSET(a, &rfds) };
        let b_ready = unsafe { libc::FD_ISSET(b, &rfds) };

        if a_ready {
            let n = unsafe { libc::read(a, buf.as_mut_ptr() as *mut _, buf.len()) };
            if n <= 0 { break; }
            let n = n as usize;
            if unsafe { libc::write(b, buf.as_ptr() as *const _, n) } != n as libc::ssize_t { break; }
        }
        if b_ready {
            let n = unsafe { libc::read(b, buf.as_mut_ptr() as *mut _, buf.len()) };
            if n <= 0 { break; }
            let n = n as usize;
            if unsafe { libc::write(a, buf.as_ptr() as *const _, n) } != n as libc::ssize_t { break; }
        }
    }
}

fn mode_xterm(sock_path: &str) -> i32 {
    match UnixStream::connect(sock_path) {
        Err(e) => { eprintln!("port-helper: connect {}: {}", sock_path, e); 1 }
        Ok(s)  => {
            unsafe { libc::setsid() };
            bridge(0, s.as_raw_fd());
            0
        }
    }
}

fn mode_port() -> i32 {
    let kern_fd: RawFd = env::var("UML_PORT_HELPER_FD")
        .ok().and_then(|s| s.parse().ok()).unwrap_or(3);
    unsafe { libc::setsid() };
    bridge(0, kern_fd);
    0
}

fn main() {
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    let args: Vec<String> = env::args().collect();
    let code = if args.len() >= 3 && args[1] == "-uml-socket" {
        mode_xterm(&args[2])
    } else {
        mode_port()
    };
    std::process::exit(code);
}
