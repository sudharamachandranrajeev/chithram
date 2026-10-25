//! Linux: fork; in the child PDEATHSIG + rlimits + NO_NEW_PRIVS + Landlock
//! (read-only allowlist) + seccomp-bpf, then execve. The parent enforces the
//! wall-clock limit.

use crate::Opts;
use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::time::{Duration, Instant};

const DEFAULT_RO: &[&str] = &[
    "/usr", "/lib", "/lib64", "/lib32", "/bin", "/sbin", "/etc/ld.so.cache", "/etc/ld.so.conf",
    "/etc/ld.so.conf.d", "/etc/localtime", "/dev/urandom", "/proc/self",
];

pub fn run(o: Opts) -> i32 {
    let ppid = unsafe { libc::getpid() };
    let pid = unsafe { libc::fork() };
    if pid < 0 {
        eprintln!("nova-sandbox: fork failed");
        return 111;
    }
    if pid == 0 {
        child(&o, ppid);
    }
    let start = Instant::now();
    let limit = Duration::from_secs(o.timeout_s);
    loop {
        let mut st: libc::c_int = 0;
        let r = unsafe { libc::waitpid(pid, &mut st, libc::WNOHANG) };
        if r == pid {
            if libc::WIFEXITED(st) {
                return libc::WEXITSTATUS(st);
            }
            if libc::WIFSIGNALED(st) {
                return 128 + libc::WTERMSIG(st);
            }
            return 111;
        }
        if r < 0 {
            return 111;
        }
        if start.elapsed() > limit {
            unsafe {
                libc::kill(pid, libc::SIGKILL);
                libc::waitpid(pid, &mut st, 0);
            }
            eprintln!("nova-sandbox: wall timeout ({}s), killed", o.timeout_s);
            return 124;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn die(msg: &str) -> ! {
    note(msg);
    unsafe { libc::_exit(111) }
}

/// Best-effort stderr line for the child: under RLIMIT_FSIZE 0 a file-backed
/// stderr fails with EFBIG, and eprintln! would panic on that.
fn note(msg: &str) {
    use std::io::Write;
    let _ = writeln!(std::io::stderr(), "nova-sandbox: {msg}");
}

fn child(o: &Opts, parent: libc::pid_t) -> ! {
    unsafe {
        if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL as libc::c_ulong, 0 as libc::c_ulong, 0 as libc::c_ulong, 0 as libc::c_ulong) != 0 {
            die("PDEATHSIG failed");
        }
        if libc::getppid() != parent {
            libc::_exit(111); // parent already gone
        }
        libc::setsid();
        // With RLIMIT_FSIZE 0 a write to a regular file raises SIGXFSZ, which
        // would kill us when stderr is redirected to a file. Ignored (kept
        // across execve), such writes fail with EFBIG instead.
        libc::signal(libc::SIGXFSZ, libc::SIG_IGN);
        set_limit(libc::RLIMIT_AS, o.mem_mib * 1024 * 1024);
        set_limit(libc::RLIMIT_CPU, o.cpu_s);
        set_limit(libc::RLIMIT_NOFILE, 64);
        set_limit(libc::RLIMIT_FSIZE, 0);
        set_limit(libc::RLIMIT_CORE, 0);
        if libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1 as libc::c_ulong, 0 as libc::c_ulong, 0 as libc::c_ulong, 0 as libc::c_ulong) != 0 {
            die("NO_NEW_PRIVS failed");
        }
    }
    if let Some(cwd) = &o.cwd {
        if std::env::set_current_dir(cwd).is_err() {
            die("cannot enter --cwd");
        }
    }
    // Interpreter should not try to write bytecode (writes are denied anyway).
    std::env::set_var("PYTHONDONTWRITEBYTECODE", "1");

    let abi = landlock(o);
    let prog = CString::new(o.cmd[0].as_bytes()).unwrap_or_else(|_| die("bad program path"));
    let args: Vec<CString> = o.cmd.iter().map(|a| CString::new(a.as_bytes()).unwrap()).collect();
    let mut argv: Vec<*const libc::c_char> = args.iter().map(|a| a.as_ptr()).collect();
    argv.push(std::ptr::null());
    let env: Vec<CString> = std::env::vars_os()
        .map(|(k, v)| {
            let mut b = k.as_bytes().to_vec();
            b.push(b'=');
            b.extend_from_slice(v.as_bytes());
            CString::new(b).unwrap()
        })
        .collect();
    let mut envp: Vec<*const libc::c_char> = env.iter().map(|a| a.as_ptr()).collect();
    envp.push(std::ptr::null());

    seccomp(prog.as_ptr() as u64);
    note(&format!("layers landlock_abi={abi} seccomp=on rlimits=on pdeathsig=on"));
    unsafe {
        libc::execve(prog.as_ptr(), argv.as_ptr(), envp.as_ptr());
        let e = *libc::__errno_location();
        note(&format!("execve failed errno={e}"));
        libc::_exit(111)
    }
}

unsafe fn set_limit(res: libc::__rlimit_resource_t, v: u64) {
    let r = libc::rlimit { rlim_cur: v as libc::rlim_t, rlim_max: v as libc::rlim_t };
    if libc::setrlimit(res, &r) != 0 {
        die("setrlimit failed");
    }
}

// ---- Landlock ---------------------------------------------------------------

#[repr(C, packed)]
struct PathBeneath {
    allowed_access: u64,
    parent_fd: i32,
}

const SYS_LL_CREATE: libc::c_long = 444;
const SYS_LL_ADD: libc::c_long = 445;
const SYS_LL_RESTRICT: libc::c_long = 446;

/// Returns the Landlock ABI used (0 = unavailable but allowed by flag).
fn landlock(o: &Opts) -> i64 {
    unsafe {
        let abi = libc::syscall(SYS_LL_CREATE, std::ptr::null::<u8>(), 0usize, 1u32);
        if abi < 1 {
            if o.allow_no_landlock {
                note("WARNING Landlock unavailable, continuing without it");
                return 0;
            }
            die("Landlock unavailable (use --allow-no-landlock to run without it)");
        }
        // Every filesystem right the kernel knows at this ABI is "handled" (so denied
        // unless a rule grants it). Only execute+read are ever granted.
        let mut handled: u64 = (1 << 13) - 1; // v1: bits 0..12
        if abi >= 2 {
            handled |= 1 << 13; // REFER
        }
        if abi >= 3 {
            handled |= 1 << 14; // TRUNCATE
        }
        if abi >= 5 {
            handled |= 1 << 15; // IOCTL_DEV
        }
        let attr: [u64; 1] = [handled];
        let fd = libc::syscall(SYS_LL_CREATE, attr.as_ptr(), 8usize, 0u32) as i32;
        if fd < 0 {
            die("landlock_create_ruleset failed");
        }
        let allow: u64 = 1 /*EXECUTE*/ | 4 /*READ_FILE*/ | 8 /*READ_DIR*/;
        let mut paths: Vec<std::path::PathBuf> = DEFAULT_RO.iter().map(|p| p.into()).collect();
        paths.extend(o.ro.iter().cloned());
        for p in paths {
            let c = match CString::new(p.as_os_str().as_bytes()) {
                Ok(c) => c,
                Err(_) => continue,
            };
            let pfd = libc::open(c.as_ptr(), libc::O_PATH | libc::O_CLOEXEC);
            if pfd < 0 {
                continue; // missing path: nothing to allow
            }
            let rule = PathBeneath { allowed_access: allow, parent_fd: pfd };
            // A file (not a dir) may not carry directory rights.
            let mut st: libc::stat = std::mem::zeroed();
            let is_dir = libc::fstat(pfd, &mut st) == 0 && (st.st_mode & libc::S_IFMT) == libc::S_IFDIR;
            let rule = if is_dir { rule } else { PathBeneath { allowed_access: allow & !8, parent_fd: pfd } };
            if libc::syscall(SYS_LL_ADD, fd, 1u32, &rule as *const PathBeneath, 0u32) != 0 {
                die(&format!("landlock_add_rule failed for {}", p.display()));
            }
            libc::close(pfd);
        }
        if libc::syscall(SYS_LL_RESTRICT, fd, 0u32) != 0 {
            die("landlock_restrict_self failed");
        }
        libc::close(fd);
        abi as i64
    }
}

// ---- seccomp-bpf --------------------------------------------------------------

#[cfg(target_arch = "x86_64")]
const AUDIT_ARCH: u32 = 0xC000_003E;
#[cfg(target_arch = "aarch64")]
const AUDIT_ARCH: u32 = 0xC000_00B7;

const BPF_LD_W_ABS: u16 = 0x20; // BPF_LD | BPF_W | BPF_ABS
const BPF_JEQ_K: u16 = 0x15; // BPF_JMP | BPF_JEQ | BPF_K
const BPF_JSET_K: u16 = 0x45;
const BPF_JGE_K: u16 = 0x35;
const BPF_AND_K: u16 = 0x54; // BPF_ALU | BPF_AND | BPF_K
const BPF_RET_K: u16 = 0x06;

const RET_ALLOW: u32 = 0x7fff_0000;
const RET_KILL_PROCESS: u32 = 0x8000_0000;
const RET_ERRNO: u32 = 0x0005_0000;

fn ins(code: u16, jt: u8, jf: u8, k: u32) -> libc::sock_filter {
    libc::sock_filter { code, jt, jf, k }
}
fn ld(off: u32) -> libc::sock_filter {
    ins(BPF_LD_W_ABS, 0, 0, off)
}
const OFF_NR: u32 = 0;
const OFF_ARCH: u32 = 4;
fn arg_lo(i: u32) -> u32 {
    16 + 8 * i
}
fn arg_hi(i: u32) -> u32 {
    16 + 8 * i + 4
}

/// Syscalls refused outright with EPERM.
fn deny_list() -> Vec<libc::c_long> {
    let mut v = vec![
        // network and IPC sockets of every family (INET, INET6, NETLINK, PACKET, UNIX)
        libc::SYS_socket, libc::SYS_socketpair, libc::SYS_connect, libc::SYS_bind, libc::SYS_listen,
        // debugging and cross-process access
        libc::SYS_ptrace, libc::SYS_process_vm_readv, libc::SYS_process_vm_writev, libc::SYS_kill,
        libc::SYS_tkill, libc::SYS_pidfd_open, libc::SYS_pidfd_getfd,
        // filesystem mutation
        libc::SYS_unlinkat, libc::SYS_renameat, libc::SYS_renameat2, libc::SYS_mkdirat,
        libc::SYS_mknodat, libc::SYS_symlinkat, libc::SYS_linkat, libc::SYS_truncate,
        libc::SYS_ftruncate, libc::SYS_fchmod, libc::SYS_fchmodat, libc::SYS_fchown,
        libc::SYS_fchownat, libc::SYS_setxattr, libc::SYS_lsetxattr, libc::SYS_fsetxattr,
        libc::SYS_removexattr, libc::SYS_lremovexattr, libc::SYS_fremovexattr, libc::SYS_fallocate,
        libc::SYS_memfd_create,
        // exec after start, process creation
        libc::SYS_execveat,
        // kernel attack surface
        libc::SYS_mount, libc::SYS_umount2, libc::SYS_pivot_root, libc::SYS_chroot, libc::SYS_setns,
        libc::SYS_unshare, libc::SYS_bpf, libc::SYS_io_uring_setup, libc::SYS_io_uring_enter,
        libc::SYS_io_uring_register, libc::SYS_perf_event_open, libc::SYS_userfaultfd,
        libc::SYS_kexec_load, libc::SYS_init_module, libc::SYS_finit_module, libc::SYS_delete_module,
        libc::SYS_keyctl, libc::SYS_add_key, libc::SYS_request_key,
    ];
    #[cfg(target_arch = "x86_64")]
    v.extend_from_slice(&[
        libc::SYS_unlink, libc::SYS_rmdir, libc::SYS_rename, libc::SYS_mkdir, libc::SYS_mknod,
        libc::SYS_symlink, libc::SYS_link, libc::SYS_chmod, libc::SYS_chown, libc::SYS_lchown,
        libc::SYS_creat, libc::SYS_fork, libc::SYS_vfork,
    ]);
    v
}

fn seccomp(exec_ptr: u64) {
    let mut f: Vec<libc::sock_filter> = Vec::new();
    // Wrong architecture (or x32 ABI): kill.
    f.push(ld(OFF_ARCH));
    f.push(ins(BPF_JEQ_K, 1, 0, AUDIT_ARCH));
    f.push(ins(BPF_RET_K, 0, 0, RET_KILL_PROCESS));
    f.push(ld(OFF_NR));
    #[cfg(target_arch = "x86_64")]
    {
        f.push(ins(BPF_JGE_K, 0, 1, 0x4000_0000));
        f.push(ins(BPF_RET_K, 0, 0, RET_KILL_PROCESS));
    }
    for nr in deny_list() {
        f.push(ins(BPF_JEQ_K, 0, 1, nr as u32));
        f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::EPERM as u32));
    }
    // clone3 / openat2: ENOSYS so libc falls back to clone / openat (which we can inspect).
    for nr in [libc::SYS_clone3, libc::SYS_openat2] {
        f.push(ins(BPF_JEQ_K, 0, 1, nr as u32));
        f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::ENOSYS as u32));
    }
    // clone without CLONE_THREAD is a fork: refuse. Threads are fine.
    f.push(ins(BPF_JEQ_K, 0, 4, libc::SYS_clone as u32));
    f.push(ld(arg_lo(0)));
    f.push(ins(BPF_JSET_K, 1, 0, 0x0001_0000));
    f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::EPERM as u32));
    f.push(ld(OFF_NR));
    // open / openat with any write-ish flag: EACCES.
    let wr_mask: u32 = 0o3 | 0o100 | 0o1000 | 0o2000; // ACCMODE | CREAT | TRUNC | APPEND
    let tmpfile: u32 = 0o20200000;
    let mut open_rule = |nr: libc::c_long, flag_arg: u32| {
        f.push(ins(BPF_JEQ_K, 0, 7, nr as u32));
        f.push(ld(arg_lo(flag_arg)));
        f.push(ins(BPF_JSET_K, 0, 1, wr_mask));
        f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::EACCES as u32));
        f.push(ins(BPF_AND_K, 0, 0, tmpfile));
        f.push(ins(BPF_JEQ_K, 0, 1, tmpfile));
        f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::EACCES as u32));
        f.push(ld(OFF_NR));
    };
    open_rule(libc::SYS_openat, 2);
    #[cfg(target_arch = "x86_64")]
    open_rule(libc::SYS_open, 1);
    // execve: only the launcher's own call (same path pointer) once; afterwards refused.
    f.push(ins(BPF_JEQ_K, 0, 6, libc::SYS_execve as u32));
    f.push(ld(arg_lo(0)));
    f.push(ins(BPF_JEQ_K, 0, 2, (exec_ptr & 0xffff_ffff) as u32));
    f.push(ld(arg_hi(0)));
    f.push(ins(BPF_JEQ_K, 1, 0, (exec_ptr >> 32) as u32));
    f.push(ins(BPF_RET_K, 0, 0, RET_ERRNO | libc::EPERM as u32));
    f.push(ins(BPF_RET_K, 0, 0, RET_ALLOW));
    f.push(ins(BPF_RET_K, 0, 0, RET_ALLOW));

    let prog = libc::sock_fprog { len: f.len() as u16, filter: f.as_mut_ptr() };
    let r = unsafe { libc::prctl(libc::PR_SET_SECCOMP, 2 as libc::c_ulong /* FILTER */, &prog as *const libc::sock_fprog as libc::c_ulong, 0 as libc::c_ulong, 0 as libc::c_ulong) };
    if r != 0 {
        die("seccomp filter install failed");
    }
}
