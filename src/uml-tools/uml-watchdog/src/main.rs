// SPDX-License-Identifier: GPL-2.0
//! uml_watchdog — UML hardware watchdog daemon
//!
//! Modes: -pid <pid> | -mconsole <socket>
//! FDs: 3=ping_in, 4=ack_out
//! Kills UML if no ping within WATCHDOG_TIMEOUT seconds.

use std::env;
use std::os::unix::net::UnixStream;
use std::os::unix::io::AsRawFd;
use std::time::Duration;

const WATCHDOG_TIMEOUT: libc::time_t = 60;
const PING_FD: libc::c_int = 3;
const ACK_FD: libc::c_int = 4;

fn kill_uml(pid: libc::pid_t, reason: &str) -> ! {
    eprintln!("uml_watchdog: {} — killing UML (pid {})", reason, pid);
    if pid > 0 { unsafe { libc::kill(pid, libc::SIGKILL) }; }
    std::process::exit(1);
}

fn select_fd_timeout(fd: libc::c_int, secs: libc::time_t) -> bool {
    unsafe {
        let mut rfds = std::mem::zeroed::<libc::fd_set>();
        libc::FD_ZERO(&mut rfds);
        libc::FD_SET(fd, &mut rfds);
        let mut tv = libc::timeval { tv_sec: secs, tv_usec: 0 };
        let r = libc::select(fd + 1, &mut rfds, std::ptr::null_mut(),
                             std::ptr::null_mut(), &mut tv);
        if r < 0 && *libc::__errno_location() == libc::EINTR {
            return select_fd_timeout(fd, secs);
        }
        r > 0
    }
}

fn mode_pid(pid: libc::pid_t) {
    let mut buf = [0u8; 1];
    loop {
        if !select_fd_timeout(PING_FD, WATCHDOG_TIMEOUT) {
            kill_uml(pid, "timeout — UML hung");
        }
        let n = unsafe { libc::read(PING_FD, buf.as_mut_ptr() as *mut _, 1) };
        if n <= 0 { kill_uml(pid, "kernel pipe closed"); }
        unsafe { libc::write(ACK_FD, buf.as_ptr() as *const _, 1) };
    }
}

fn mode_mconsole(sock_path: &str) {
    let stream = (0..30).find_map(|_| {
        UnixStream::connect(sock_path).ok().or_else(|| {
            std::thread::sleep(Duration::from_secs(1)); None
        })
    }).unwrap_or_else(|| {
        eprintln!("uml_watchdog: cannot connect to {}", sock_path);
        std::process::exit(1);
    });

    let sock = stream.as_raw_fd();
    let max = sock.max(PING_FD);
    let mut buf = [0u8; 256];

    loop {
        unsafe {
            let mut rfds = std::mem::zeroed::<libc::fd_set>();
            libc::FD_ZERO(&mut rfds);
            libc::FD_SET(sock, &mut rfds);
            libc::FD_SET(PING_FD, &mut rfds);
            let mut tv = libc::timeval { tv_sec: WATCHDOG_TIMEOUT, tv_usec: 0 };
            let r = libc::select(max + 1, &mut rfds, std::ptr::null_mut(),
                                 std::ptr::null_mut(), &mut tv);
            if r == 0 { kill_uml(0, "mconsole timeout — UML hung"); }
            if r < 0 {
                if *libc::__errno_location() == libc::EINTR { continue; }
                break;
            }
            if libc::FD_ISSET(PING_FD, &rfds) {
                let n = libc::read(PING_FD, buf.as_mut_ptr() as *mut _, 1);
                if n <= 0 { break; }
                libc::write(ACK_FD, buf.as_ptr() as *const _, 1);
            }
            if libc::FD_ISSET(sock, &rfds) {
                if libc::read(sock, buf.as_mut_ptr() as *mut _, buf.len()) <= 0 { break; }
            }
        }
    }
}

fn main() {
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: uml_watchdog -pid <pid> | -mconsole <socket>");
        std::process::exit(1);
    }
    match args[1].as_str() {
        "-pid"      => mode_pid(args[2].parse().expect("invalid pid")),
        "-mconsole" => mode_mconsole(&args[2]),
        other => { eprintln!("uml_watchdog: unknown mode: {}", other); std::process::exit(1); }
    }
}
