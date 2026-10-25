//! nova-sandbox: `nova-sandbox [options] -- <program> [args...]`
//!
//! Options:
//!   --ro <path>          extra read-only path (repeatable): program prefix, runner dir
//!   --cwd <path>         working directory for the child
//!   --timeout <secs>     wall-clock limit (default 30)
//!   --mem <MiB>          address-space / job memory limit (default 512)
//!   --cpu <secs>         CPU-time limit (default 20)
//!   --allow-no-landlock  Linux: continue if the kernel has no Landlock (default: refuse)
//!
//! Exit code: the child's, 128+signal if it was killed, 124 on wall timeout,
//! 111 if a sandbox layer could not be set up (the child never runs).
//!
//! Linux: the child runs with RLIMIT_FSIZE 0 and SIGXFSZ ignored, so writes to
//! a stdout/stderr redirected to a regular file fail with EFBIG; give it pipes.

use std::ffi::OsString;
use std::path::PathBuf;

pub struct Opts {
    pub ro: Vec<PathBuf>,
    pub cwd: Option<PathBuf>,
    pub timeout_s: u64,
    pub mem_mib: u64,
    pub cpu_s: u64,
    pub allow_no_landlock: bool,
    pub cmd: Vec<OsString>,
}

fn parse() -> Result<Opts, String> {
    let mut o = Opts {
        ro: vec![],
        cwd: None,
        timeout_s: 30,
        mem_mib: 512,
        cpu_s: 20,
        allow_no_landlock: false,
        cmd: vec![],
    };
    let mut it = std::env::args_os().skip(1);
    while let Some(a) = it.next() {
        let s = a.to_string_lossy().to_string();
        match s.as_str() {
            "--" => {
                o.cmd = it.collect();
                break;
            }
            "--ro" => o.ro.push(PathBuf::from(it.next().ok_or("--ro needs a value")?)),
            "--cwd" => o.cwd = Some(PathBuf::from(it.next().ok_or("--cwd needs a value")?)),
            "--timeout" => o.timeout_s = num(it.next())?,
            "--mem" => o.mem_mib = num(it.next())?,
            "--cpu" => o.cpu_s = num(it.next())?,
            "--allow-no-landlock" => o.allow_no_landlock = true,
            other => return Err(format!("unknown option {other}")),
        }
    }
    if o.cmd.is_empty() {
        return Err("no command after --".into());
    }
    Ok(o)
}

fn num(v: Option<OsString>) -> Result<u64, String> {
    v.and_then(|s| s.to_string_lossy().parse().ok()).ok_or_else(|| "bad number".to_string())
}

#[cfg(target_os = "linux")]
mod linux;
#[cfg(windows)]
mod win;

fn main() {
    let opts = match parse() {
        Ok(o) => o,
        Err(e) => {
            eprintln!("nova-sandbox: {e}");
            std::process::exit(2);
        }
    };
    #[cfg(target_os = "linux")]
    let code = linux::run(opts);
    #[cfg(windows)]
    let code = win::run(opts);
    #[cfg(not(any(target_os = "linux", windows)))]
    let code = {
        let _ = opts;
        eprintln!("nova-sandbox: unsupported platform");
        111
    };
    std::process::exit(code);
}
