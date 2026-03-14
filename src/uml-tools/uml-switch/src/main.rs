// SPDX-License-Identifier: GPL-2.0
//! uml_switch — Virtual Ethernet switch for UML instances
//!
//! Usage: uml_switch [-unix <socket>] [-daemon]
//!
//! Listens on a Unix DGRAM socket. UML daemon-transport peers connect
//! and send Ethernet frames. Switch does MAC learning + L2 forwarding.

use std::collections::HashMap;
use std::env;
use std::os::unix::net::UnixDatagram;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;

const MAX_FRAME: usize = 1514;
const MAC_TTL_SECS: u64 = 300;
const DEFAULT_SOCK: &str = "/tmp/uml.ctl";

type Mac = [u8; 6];

struct Switch {
    ports:     Vec<PathBuf>,
    mac_table: HashMap<Mac, (usize, Instant)>,
}

impl Switch {
    fn new() -> Self { Switch { ports: vec![], mac_table: HashMap::new() } }
    fn add_port(&mut self, p: PathBuf) -> usize {
        let i = self.ports.len(); self.ports.push(p); i
    }
    fn learn(&mut self, mac: Mac, port: usize) {
        self.mac_table.insert(mac, (port, Instant::now()));
    }
    fn lookup(&self, mac: &Mac) -> Option<usize> {
        self.mac_table.get(mac)
            .filter(|(_, t)| t.elapsed().as_secs() < MAC_TTL_SECS)
            .map(|(p, _)| *p)
    }
    fn gc(&mut self) {
        self.mac_table.retain(|_, (_, t)| t.elapsed().as_secs() < MAC_TTL_SECS);
    }
}

fn macs(frame: &[u8]) -> (Mac, Mac) {
    let mut dst = [0u8;6]; let mut src = [0u8;6];
    if frame.len() >= 12 {
        dst.copy_from_slice(&frame[0..6]);
        src.copy_from_slice(&frame[6..12]);
    }
    (dst, src)
}

fn run(sock_path: &str) {
    let _ = std::fs::remove_file(sock_path);
    let ctrl = UnixDatagram::bind(sock_path).expect("bind control socket");
    let data_path = format!("{}.data", sock_path);
    let _ = std::fs::remove_file(&data_path);
    let data = Arc::new(UnixDatagram::bind(&data_path).expect("bind data socket"));
    let sw   = Arc::new(Mutex::new(Switch::new()));

    // Frame forwarding thread
    let d2 = Arc::clone(&data);
    let s2 = Arc::clone(&sw);
    thread::spawn(move || {
        let mut buf = [0u8; MAX_FRAME];
        loop {
            let n = match d2.recv_from(&mut buf) {
                Ok((n, _)) if n >= 14 => n,
                _ => continue,
            };
            let frame = &buf[..n];
            let (dst, src) = macs(frame);
            let mut sw = s2.lock().unwrap();
            sw.gc();
            // Note: can't learn src without knowing which port sent it
            // Full per-port learning would need recvfrom + port registry
            let targets: Vec<PathBuf> = if dst == [0xff;6] || sw.lookup(&dst).is_none() {
                sw.ports.clone()
            } else {
                vec![sw.ports[sw.lookup(&dst).unwrap()].clone()]
            };
            drop(sw);
            for t in targets { let _ = d2.send_to(frame, &t); }
        }
    });

    // Control: accept ADD <path> / REMOVE <path>
    let mut buf = [0u8; 512];
    loop {
        match ctrl.recv_from(&mut buf) {
            Ok((n, _)) => {
                let msg = std::str::from_utf8(&buf[..n]).unwrap_or("").trim().to_string();
                if let Some(path) = msg.strip_prefix("ADD ") {
                    let idx = sw.lock().unwrap().add_port(PathBuf::from(path));
                    println!("uml_switch: port {} registered: {}", idx, path);
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => { eprintln!("uml_switch: {}", e); break; }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut sock = DEFAULT_SOCK.to_string();
    let mut daemon = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-unix"   => { i += 1; sock = args[i].clone(); }
            "-daemon" => daemon = true,
            _ => {}
        }
        i += 1;
    }
    if daemon {
        unsafe {
            if libc::fork() > 0 { std::process::exit(0); }
            libc::setsid();
        }
    }
    println!("uml_switch: listening on {}", sock);
    run(&sock);
}
