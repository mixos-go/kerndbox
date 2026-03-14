// SPDX-License-Identifier: GPL-2.0
//! uml_mconsole — UML management console client
//!
//! Usage:
//!   uml_mconsole <umid|socket> [command [args...]]
//!   uml_mconsole <umid|socket>  (interactive)
//!
//! Protocol: mconsole DGRAM socket, magic 0xcafebabe
//!   Request:  magic(u32) + id(u32) + len(u16) + data[512]
//!   Reply:    magic(u32) + err(i32) + more(i32) + len(u16) + data[512]

use std::env;
use std::io::{self, BufRead, Write};
use std::os::unix::net::UnixDatagram;
use std::path::{Path, PathBuf};

const MCONSOLE_MAGIC: u32 = 0xcafebabe;
const MAX_DATA: usize = 512;

#[repr(C, packed)]
struct McRequest {
    magic: u32,
    id:    u32,
    len:   u16,
    data:  [u8; MAX_DATA],
}

#[repr(C, packed)]
struct McReply {
    magic: u32,
    err:   i32,
    more:  i32,
    len:   u16,
    data:  [u8; MAX_DATA],
}

fn find_socket(umid: &str) -> Option<PathBuf> {
    // Direct path
    if umid.starts_with('/') {
        let p = Path::new(umid);
        if p.exists() { return Some(p.to_path_buf()); }
    }
    // ~/.uml/<umid>/mconsole
    if let Ok(home) = env::var("HOME") {
        let p = PathBuf::from(&home).join(".uml").join(umid).join("mconsole");
        if p.exists() { return Some(p); }
    }
    // /tmp/uml-<umid>/mconsole (kerndbox convention)
    let p = PathBuf::from(format!("/tmp/uml-{}/mconsole", umid));
    if p.exists() { return Some(p); }

    None
}

fn send_command(sock_path: &Path, cmd: &str) -> io::Result<i32> {
    let tmp = format!("/tmp/uml_mc_{}", std::process::id());
    let _ = std::fs::remove_file(&tmp);

    let sock = UnixDatagram::bind(&tmp)?;
    sock.connect(sock_path)?;

    // Build request
    let mut req = McRequest {
        magic: MCONSOLE_MAGIC,
        id:    std::process::id(),
        len:   cmd.len().min(MAX_DATA) as u16,
        data:  [0u8; MAX_DATA],
    };
    req.data[..cmd.len().min(MAX_DATA)].copy_from_slice(&cmd.as_bytes()[..cmd.len().min(MAX_DATA)]);

    let req_bytes = unsafe {
        std::slice::from_raw_parts(&req as *const _ as *const u8, std::mem::size_of::<McRequest>())
    };
    sock.send(req_bytes)?;

    // Read replies
    let mut last_err = 0i32;
    loop {
        let mut reply = McReply { magic: 0, err: 0, more: 0, len: 0, data: [0u8; MAX_DATA] };
        let reply_bytes = unsafe {
            std::slice::from_raw_parts_mut(
                &mut reply as *mut _ as *mut u8, std::mem::size_of::<McReply>())
        };
        let n = sock.recv(reply_bytes)?;
        if n < 12 { break; }

        let len = reply.len as usize;
        if len > 0 && len <= MAX_DATA {
            let _ = io::stdout().write_all(&reply.data[..len]);
        }
        last_err = reply.err;
        if reply.more == 0 { break; }
    }

    let _ = std::fs::remove_file(&tmp);
    if last_err != 0 {
        eprintln!("mconsole error: {}", last_err);
    }
    Ok(last_err)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: uml_mconsole <umid|socket> [command [args...]]\n\
                   Commands: version halt reboot config remove cad stop go log proc stack sysrq");
        std::process::exit(1);
    }

    let sock_path = match find_socket(&args[1]) {
        Some(p) => p,
        None => {
            eprintln!("uml_mconsole: cannot find mconsole socket for '{}'", args[1]);
            eprintln!("  Tried: ~/.uml/{0}/mconsole, /tmp/uml-{0}/mconsole", args[1]);
            std::process::exit(1);
        }
    };

    if args.len() >= 3 {
        let cmd = args[2..].join(" ");
        match send_command(&sock_path, &cmd) {
            Ok(0)  => {},
            Ok(_)  => std::process::exit(1),
            Err(e) => { eprintln!("uml_mconsole: {}", e); std::process::exit(1); }
        }
        return;
    }

    // Interactive mode
    eprintln!("Connected to {}", sock_path.display());
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let cmd = match line { Ok(l) => l, Err(_) => break };
        if cmd.is_empty() { continue; }
        if cmd == "quit" || cmd == "exit" { break; }
        let _ = send_command(&sock_path, &cmd);
        println!();
    }
}
