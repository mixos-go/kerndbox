// SPDX-License-Identifier: GPL-2.0
//! uml_mkcow — Create UML copy-on-write backing file
//!
//! Usage: uml_mkcow <cow-file> <backing-file>
//!
//! COW v2 format: 8-byte magic "LinuCow\0" + header + bitmap + data

use std::env;
use std::fs;
use std::io::{self, Write};

const COW_MAGIC:   &[u8; 8] = b"LinuCow\0";
const COW_VERSION: u32 = 2;
const SECTOR_SIZE: u32 = 512;

#[repr(C, packed)]
struct CowHeaderV2 {
    magic:         [u8; 8],
    version:       u32,
    backing_file:  [u8; 1024],
    mtime:         u64,
    size:          u64,
    sectorsize:    u32,
    alignment:     u32,
    bitmap_offset: u32,
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: uml_mkcow <cow-file> <backing-file>");
        std::process::exit(1);
    }

    let cow_path  = &args[1];
    let back_path = &args[2];

    let meta = fs::metadata(back_path)
        .map_err(|e| { eprintln!("{}: {}", back_path, e); e })?;

    let backing_size = meta.len();
    let mtime = meta.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let nsectors = (backing_size + SECTOR_SIZE as u64 - 1) / SECTOR_SIZE as u64;
    let bitmap_bytes = ((nsectors + 7) / 8) as usize;
    let bitmap_offset = std::mem::size_of::<CowHeaderV2>() as u32;

    let mut backing_buf = [0u8; 1024];
    let blen = back_path.len().min(1023);
    backing_buf[..blen].copy_from_slice(&back_path.as_bytes()[..blen]);

    let hdr = CowHeaderV2 {
        magic:         *COW_MAGIC,
        version:       COW_VERSION,
        backing_file:  backing_buf,
        mtime,
        size:          backing_size,
        sectorsize:    SECTOR_SIZE,
        alignment:     0,
        bitmap_offset,
    };

    let hdr_bytes = unsafe {
        std::slice::from_raw_parts(
            &hdr as *const _ as *const u8,
            std::mem::size_of::<CowHeaderV2>())
    };

    let mut f = fs::File::create(cow_path)
        .map_err(|e| { eprintln!("{}: {}", cow_path, e); e })?;

    f.write_all(hdr_bytes)?;
    f.write_all(&vec![0u8; bitmap_bytes])?;

    println!("Created COW file: {}", cow_path);
    println!("  Backing: {} ({} bytes, {} sectors)", back_path, backing_size, nsectors);
    Ok(())
}
