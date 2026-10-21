use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::os::fd::AsRawFd;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

const FAILURE: &str =
    "Mihomo configuration rendering failed; check private inputs and runtime paths";
const FIELDS: [&str; 5] = ["primary", "quattro", "hwid", "hostname", "token"];

pub fn normalize_newlines(value: String) -> String {
    if !value.contains('\r') {
        return value;
    }
    // Match Python's universal-newline text reader without trimming SOPS values.
    let mut output = String::with_capacity(value.len());
    let mut chars = value.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\r' {
            output.push('\n');
            chars.next_if_eq(&'\n');
        } else {
            output.push(c);
        }
    }
    output
}

fn read_text(path: &Path) -> Result<String, ()> {
    fs::read_to_string(path).map(normalize_newlines).map_err(|_| ())
}

pub fn normalize_input(mode: &str, mut value: String) -> Result<String, ()> {
    match mode {
        "legacy" => {
            // Python str.split also treats these four C0 separators as whitespace.
            value.retain(|c| !c.is_whitespace() && !matches!(c, '\u{1c}'..='\u{1f}'));
        }
        "sops" => {}
        _ => return Err(()),
    }
    if value.is_empty() { Err(()) } else { Ok(value) }
}

fn scalar(value: &str) -> Result<String, ()> {
    let json = serde_json::to_string(value).map_err(|_| ())?;
    let mut escaped = String::with_capacity(json.len());
    for c in json.chars() {
        // JSON alone leaves these YAML controls and folding characters literal.
        if matches!(c, '\u{7f}'..='\u{9f}' | '\u{2028}' | '\u{2029}') {
            write!(escaped, "\\u{:04x}", c as u32).map_err(|_| ())?;
        } else {
            escaped.push(c);
        }
    }
    Ok(escaped)
}

pub fn render(
    template: &str,
    primary: &str,
    quattro: &str,
    hwid: &str,
    hostname: &str,
    token: &str,
) -> Result<String, ()> {
    let values = [
        scalar(primary)?,
        scalar(quattro)?,
        scalar(hwid)?,
        scalar(hostname)?,
        scalar(token)?,
    ];
    let mut seen = [false; FIELDS.len()];
    let mut output = String::with_capacity(template.len());
    let mut rest = template;
    while let Some(dollar) = rest.find('$') {
        output.push_str(&rest[..dollar]);
        rest = &rest[dollar + 1..];
        if let Some(tail) = rest.strip_prefix('$') {
            output.push('$');
            rest = tail;
            continue;
        }
        let braced = rest.starts_with('{');
        let field = if braced { &rest[1..] } else { rest };
        let length = field.bytes().take_while(|c| c.is_ascii_alphanumeric() || *c == b'_').count();
        if length == 0 || field.as_bytes()[0].is_ascii_digit() {
            return Err(());
        }
        let name = &field[..length];
        rest = &field[length..];
        if braced {
            rest = rest.strip_prefix('}').ok_or(())?;
        }
        let index = FIELDS.iter().position(|candidate| *candidate == name).ok_or(())?;
        seen[index] = true;
        output.push_str(&values[index]);
    }
    output.push_str(rest);
    if seen.into_iter().all(|present| present) { Ok(output) } else { Err(()) }
}

fn publish(path: &Path, content: &str, permissions: libc::mode_t, uid: libc::uid_t) -> Result<(), ()> {
    let parent = path.parent().filter(|parent| !parent.as_os_str().is_empty()).unwrap_or(Path::new("."));
    // NamedTempFile starts at 0600, uses exclusive creation, and unlinks on error.
    let mut temporary = tempfile::Builder::new()
        .prefix(".mihomo-config.")
        .tempfile_in(parent)
        .map_err(|_| ())?;
    temporary.write_all(content.as_bytes()).map_err(|_| ())?;
    let fd = temporary.as_file().as_raw_fd();
    // SAFETY: fd remains open and owned by temporary throughout both calls.
    if unsafe { libc::fchown(fd, uid, !0 as libc::gid_t) } != 0
        || unsafe { libc::fchmod(fd, permissions) } != 0
    {
        return Err(());
    }
    temporary.persist(path).map_err(|_| ())?;
    Ok(())
}

fn run() -> Result<(), ()> {
    // SAFETY: this executable is single-threaded and sets its mask before file creation.
    unsafe { libc::umask(0o077) };
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 9 {
        return Err(());
    }
    let mode = args[0].to_str().ok_or(())?;
    if !matches!(mode, "legacy" | "sops") {
        return Err(());
    }
    let hostname = args[1].to_str().ok_or(())?;
    let template = read_text(Path::new(&args[2]))?;
    let primary = normalize_input(mode, read_text(Path::new(&args[3]))?)?;
    let quattro = normalize_input(mode, read_text(Path::new(&args[4]))?)?;
    let hwid = normalize_input(mode, read_text(Path::new(&args[5]))?)?;
    let username = CString::new(args[8].as_os_str().as_bytes()).map_err(|_| ())?;
    // SAFETY: the C string is terminated, and no other thread can invalidate getpwnam's storage.
    let account = unsafe { libc::getpwnam(username.as_ptr()) };
    if account.is_null() {
        return Err(());
    }
    // SAFETY: getpwnam succeeded, and its storage has not been reused.
    let uid = unsafe { (*account).pw_uid };
    let mut random = [0u8; 32];
    getrandom::fill(&mut random).map_err(|_| ())?;
    let token = URL_SAFE_NO_PAD.encode(random);
    let result = render(&template, &primary, &quattro, &hwid, hostname, &token)?;
    // Publish authentication first. Any failure prevents the dependent service from starting.
    publish(Path::new(&args[7]), &format!("Authorization: Bearer {token}\n"), 0o400, uid)?;
    // SAFETY: getuid has no preconditions.
    publish(Path::new(&args[6]), &result, 0o600, unsafe { libc::getuid() })
}

fn main() {
    if run().is_err() {
        eprintln!("{FAILURE}");
        std::process::exit(1);
    }
}
