//! Windows: AppContainer with NO capabilities (no network, no profile access),
//! read-only ACL grants for the allowlisted paths, plus a Job Object
//! (memory, 1 process, CPU time, UI restrictions, kill on close).

use crate::Opts;
use std::ffi::{OsStr, OsString};
use std::os::windows::ffi::OsStrExt;
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Security::Authorization::*;
use windows_sys::Win32::Security::Isolation::*;
use windows_sys::Win32::Security::*;
use windows_sys::Win32::Storage::FileSystem::{FILE_GENERIC_EXECUTE, FILE_GENERIC_READ};
use windows_sys::Win32::System::Console::*;
use windows_sys::Win32::System::JobObjects::*;
use windows_sys::Win32::System::Threading::*;

const PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES: usize = 0x0002_0009;
const PROC_THREAD_ATTRIBUTE_HANDLE_LIST: usize = 0x0002_0002;
const HRESULT_ALREADY_EXISTS: i32 = 0x800700B7u32 as i32;
const PROFILE: &str = "dev.chithram.nova.sandbox";

fn wide(s: &OsStr) -> Vec<u16> {
    s.encode_wide().chain(std::iter::once(0)).collect()
}

fn quote(arg: &OsStr) -> Vec<u16> {
    let w: Vec<u16> = arg.encode_wide().collect();
    if !w.is_empty() && !w.iter().any(|&c| c == b' ' as u16 || c == b'\t' as u16 || c == b'"' as u16) {
        return w;
    }
    let mut out = vec![b'"' as u16];
    let mut bs = 0usize;
    for &c in &w {
        if c == b'\\' as u16 {
            bs += 1;
        } else if c == b'"' as u16 {
            out.extend(std::iter::repeat(b'\\' as u16).take(bs * 2 + 1));
            out.push(c);
            bs = 0;
        } else {
            out.extend(std::iter::repeat(b'\\' as u16).take(bs));
            out.push(c);
            bs = 0;
        }
    }
    out.extend(std::iter::repeat(b'\\' as u16).take(bs * 2));
    out.push(b'"' as u16);
    out
}

unsafe fn appcontainer_sid() -> Result<PSID, String> {
    let name = wide(OsStr::new(PROFILE));
    let disp = wide(OsStr::new("Chithram nova sandbox"));
    let mut sid: PSID = null_mut();
    let hr = CreateAppContainerProfile(name.as_ptr(), disp.as_ptr(), disp.as_ptr(), null(), 0, &mut sid);
    if hr == 0 {
        return Ok(sid);
    }
    if hr == HRESULT_ALREADY_EXISTS {
        let hr2 = DeriveAppContainerSidFromAppContainerName(name.as_ptr(), &mut sid);
        if hr2 == 0 {
            return Ok(sid);
        }
        return Err(format!("DeriveAppContainerSid hr={hr2:#x}"));
    }
    Err(format!("CreateAppContainerProfile hr={hr:#x}"))
}

/// Add a read+execute ACE for the AppContainer SID, inherited by children.
unsafe fn grant_read(path: &std::path::Path, sid: PSID) -> Result<(), String> {
    let wpath = wide(path.as_os_str());
    let mut old: *mut ACL = null_mut();
    let mut sd: PSECURITY_DESCRIPTOR = null_mut();
    let r = GetNamedSecurityInfoW(wpath.as_ptr(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, null_mut(), null_mut(), &mut old, null_mut(), &mut sd);
    if r != 0 {
        return Err(format!("GetNamedSecurityInfo {} err={r}", path.display()));
    }
    let mut ea: EXPLICIT_ACCESS_W = std::mem::zeroed();
    ea.grfAccessPermissions = FILE_GENERIC_READ | FILE_GENERIC_EXECUTE;
    ea.grfAccessMode = GRANT_ACCESS;
    ea.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
    ea.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    ea.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP;
    ea.Trustee.ptstrName = sid as *mut u16;
    let mut new: *mut ACL = null_mut();
    let r = SetEntriesInAclW(1, &ea, old, &mut new);
    if r != 0 {
        LocalFree(sd as _);
        return Err(format!("SetEntriesInAcl err={r}"));
    }
    let r = SetNamedSecurityInfoW(wpath.as_ptr() as *mut u16, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, null_mut(), null_mut(), new, null());
    LocalFree(new as _);
    LocalFree(sd as _);
    if r != 0 {
        return Err(format!("SetNamedSecurityInfo {} err={r}", path.display()));
    }
    Ok(())
}

pub fn run(o: Opts) -> i32 {
    match unsafe { run_inner(&o) } {
        Ok(c) => c,
        Err(e) => {
            eprintln!("nova-sandbox: {e}");
            111
        }
    }
}

unsafe fn run_inner(o: &Opts) -> Result<i32, String> {
    let sid = appcontainer_sid()?;
    for p in &o.ro {
        grant_read(p, sid)?;
    }

    // Job: memory, one process, CPU time, UI restrictions, kill on close.
    let job = CreateJobObjectW(null(), null());
    if job.is_null() {
        return Err("CreateJobObject failed".into());
    }
    let mut ext: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
    ext.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_PROCESS_MEMORY
        | JOB_OBJECT_LIMIT_ACTIVE_PROCESS
        | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        | JOB_OBJECT_LIMIT_PROCESS_TIME
        | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
    ext.BasicLimitInformation.ActiveProcessLimit = 1;
    ext.BasicLimitInformation.PerProcessUserTimeLimit = (o.cpu_s as i64) * 10_000_000;
    ext.ProcessMemoryLimit = (o.mem_mib as usize) * 1024 * 1024;
    if SetInformationJobObject(job, JobObjectExtendedLimitInformation, &ext as *const _ as *const _, std::mem::size_of_val(&ext) as u32) == 0 {
        return Err(format!("SetInformationJobObject(limits) err={}", GetLastError()));
    }
    let mut ui: JOBOBJECT_BASIC_UI_RESTRICTIONS = std::mem::zeroed();
    ui.UIRestrictionsClass = 0x0000_00FF; // all JOB_OBJECT_UILIMIT_* bits
    SetInformationJobObject(job, JobObjectBasicUIRestrictions, &ui as *const _ as *const _, std::mem::size_of_val(&ui) as u32);

    // Inherit only stdin/stdout/stderr.
    let hin = GetStdHandle(STD_INPUT_HANDLE);
    let hout = GetStdHandle(STD_OUTPUT_HANDLE);
    let herr = GetStdHandle(STD_ERROR_HANDLE);
    let mut handles = [hin, hout, herr];
    for h in handles {
        SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    }

    let mut caps: SECURITY_CAPABILITIES = std::mem::zeroed();
    caps.AppContainerSid = sid;
    caps.Capabilities = null_mut();
    caps.CapabilityCount = 0;

    let mut size = 0usize;
    InitializeProcThreadAttributeList(null_mut(), 2, 0, &mut size);
    let mut buf = vec![0u8; size];
    let list = buf.as_mut_ptr() as LPPROC_THREAD_ATTRIBUTE_LIST;
    if InitializeProcThreadAttributeList(list, 2, 0, &mut size) == 0 {
        return Err(format!("InitializeProcThreadAttributeList err={}", GetLastError()));
    }
    if UpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES, &mut caps as *mut _ as *mut _, std::mem::size_of::<SECURITY_CAPABILITIES>(), null_mut(), null()) == 0 {
        return Err(format!("UpdateProcThreadAttribute(caps) err={}", GetLastError()));
    }
    if UpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles.as_mut_ptr() as *mut _, std::mem::size_of_val(&handles), null_mut(), null()) == 0 {
        return Err(format!("UpdateProcThreadAttribute(handles) err={}", GetLastError()));
    }

    let mut cmdline: Vec<u16> = Vec::new();
    for (i, a) in o.cmd.iter().enumerate() {
        if i > 0 {
            cmdline.push(b' ' as u16);
        }
        cmdline.extend(quote(a));
    }
    cmdline.push(0);
    let app = wide(&o.cmd[0]);
    let cwd: Option<Vec<u16>> = o.cwd.as_ref().map(|c| wide(c.as_os_str()));
    std::env::set_var("PYTHONDONTWRITEBYTECODE", "1");

    let mut si: STARTUPINFOEXW = std::mem::zeroed();
    si.StartupInfo.cb = std::mem::size_of::<STARTUPINFOEXW>() as u32;
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = hin;
    si.StartupInfo.hStdOutput = hout;
    si.StartupInfo.hStdError = herr;
    si.lpAttributeList = list;
    let mut pi: PROCESS_INFORMATION = std::mem::zeroed();
    let ok = CreateProcessW(
        app.as_ptr(),
        cmdline.as_mut_ptr(),
        null(),
        null(),
        1,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_NO_WINDOW,
        null(),
        cwd.as_ref().map_or(null(), |c| c.as_ptr()),
        &si.StartupInfo,
        &mut pi,
    );
    if ok == 0 {
        return Err(format!("CreateProcessW err={}", GetLastError()));
    }
    if AssignProcessToJobObject(job, pi.hProcess) == 0 {
        let e = GetLastError();
        TerminateProcess(pi.hProcess, 111);
        return Err(format!("AssignProcessToJobObject err={e}"));
    }
    eprintln!("nova-sandbox: layers appcontainer=on(no capabilities) job=on(mem={}MiB,procs=1,cpu={}s)", o.mem_mib, o.cpu_s);
    ResumeThread(pi.hThread);
    let w = WaitForSingleObject(pi.hProcess, (o.timeout_s * 1000) as u32);
    if w == WAIT_TIMEOUT {
        TerminateJobObject(job, 124);
        eprintln!("nova-sandbox: wall timeout ({}s), killed", o.timeout_s);
        return Ok(124);
    }
    let mut code: u32 = 0;
    GetExitCodeProcess(pi.hProcess, &mut code);
    let _ = OsString::new();
    Ok(code as i32)
}
