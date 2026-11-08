use std::ffi::CString;
use std::fmt::Write as _;
use std::fs::{self, File, OpenOptions};
use std::io::{ErrorKind, Read as _, Write as _};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{OpenOptionsExt as _, fchown};
use std::path::Path;

const FAILURE: &str =
    "Mihomo configuration rendering failed; check private inputs and runtime paths";
const FIELDS: [&str; 5] = ["primary", "quattro", "hwid", "hostname", "token"];

fn read_text(path: &Path) -> Result<String, ()> {
    fs::read_to_string(path).map_err(|_| ())
}

pub fn normalize_input(mut value: String) -> Result<String, ()> {
    // Preserve Python str.split's whitespace handling, including its four C0 separators.
    value.retain(|c| !c.is_whitespace() && !matches!(c, '\u{1c}'..='\u{1f}'));
    if value.is_empty() { Err(()) } else { Ok(value) }
}

pub fn normalize_hwid(value: String) -> Result<String, ()> {
    let value = normalize_input(value)?;
    if value.len() != 36 {
        return Err(());
    }
    let mut all_zero = true;
    let mut all_f = true;
    for (index, byte) in value.bytes().enumerate() {
        if matches!(index, 8 | 13 | 18 | 23) {
            if byte != b'-' {
                return Err(());
            }
        } else {
            if !byte.is_ascii_hexdigit() {
                return Err(());
            }
            all_zero &= byte == b'0';
            all_f &= matches!(byte, b'f' | b'F');
        }
    }
    if all_zero || all_f { Err(()) } else { Ok(value) }
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

fn publish(path: &Path, content: &str, mode: u32, owner: Option<u32>) -> Result<(), ()> {
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".tmp");
    let temporary = Path::new(&temporary);
    // A stale temporary from an interrupted run would block exclusive creation.
    if let Err(error) = fs::remove_file(temporary) {
        if error.kind() != ErrorKind::NotFound {
            return Err(());
        }
    }
    let published = (|| {
        // Exclusive creation never follows a planted link; the unit's UMask=0077 keeps `mode` exact.
        let mut file = OpenOptions::new().write(true).create_new(true).mode(mode).open(temporary)?;
        file.write_all(content.as_bytes())?;
        fchown(&file, owner, None)?;
        file.sync_all()?;
        fs::rename(temporary, path)
    })();
    if published.is_err() {
        let _ = fs::remove_file(temporary);
    }
    published.map_err(|_| ())
}

fn run() -> Result<(), ()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 7 {
        return Err(());
    }
    let hostname = args[0].to_str().ok_or(())?;
    let template = read_text(Path::new(&args[1]))?;
    let primary = normalize_input(read_text(Path::new(&args[2]))?)?;
    let quattro = normalize_input(read_text(Path::new(&args[3]))?)?;
    let hwid = normalize_hwid(read_text(Path::new("/sys/class/dmi/id/product_uuid"))?)?;
    let username = CString::new(args[6].as_os_str().as_bytes()).map_err(|_| ())?;
    // SAFETY: the C string is terminated, and no other thread can invalidate getpwnam's storage.
    let account = unsafe { libc::getpwnam(username.as_ptr()) };
    if account.is_null() {
        return Err(());
    }
    // SAFETY: getpwnam succeeded, and its storage has not been reused.
    let uid = unsafe { (*account).pw_uid };
    let mut random = [0u8; 32];
    File::open("/dev/urandom").and_then(|mut source| source.read_exact(&mut random)).map_err(|_| ())?;
    let token = random.iter().fold(String::with_capacity(64), |mut token, byte| {
        let _ = write!(token, "{byte:02x}");
        token
    });
    let result = render(&template, &primary, &quattro, &hwid, hostname, &token)?;
    // Publish authentication first. Any failure prevents the dependent service from starting.
    publish(Path::new(&args[5]), &format!("Authorization: Bearer {token}\n"), 0o400, Some(uid))?;
    // The root unit already owns what it creates.
    publish(Path::new(&args[4]), &result, 0o600, None)
}

fn main() {
    if run().is_err() {
        eprintln!("{FAILURE}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_inputs_and_template() {
        let uuid = "01234567-89AB-cdef-0123-456789abcdef";
        assert_eq!(normalize_input(" \r\nhttps://example.invalid/\u{a0}x\u{1c}\t".into()).unwrap(), "https://example.invalid/x");
        assert_eq!(normalize_hwid(format!("\r\n {uuid}\u{2003}")).unwrap(), uuid);
        for invalid in [
            "",
            " \r\n\u{1f}",
            "00000000-0000-0000-0000-000000000000",
            "ffffffff-ffff-FFFF-ffff-ffffffffffff",
            "0123456789abcdef0123456789abcdef",
            "01234567_89ab-cdef-0123-456789abcdef",
            "g1234567-89ab-cdef-0123-456789abcdef",
        ] {
            assert!(normalize_hwid(invalid.into()).is_err());
        }
        assert!(normalize_input(" \r\n\u{a0}\u{1c}\u{1f}".into()).is_err());
        let template = "${primary}\n${quattro}\n${hwid}\n${hostname}\n${token}\n$$";
        let primary = "https://example.invalid/\"\\\u{85}\u{2028}";
        let output = render(template, primary, "quattro", uuid, "host", "token").unwrap();
        let mut lines = output.lines();
        for expected in [primary, "quattro", uuid, "host", "token"] {
            assert_eq!(serde_json::from_str::<String>(lines.next().unwrap()).unwrap(), expected);
        }
        assert_eq!(lines.next(), Some("$"));
        assert!(render("${unknown}", primary, "quattro", uuid, "host", "token").is_err());
        assert!(render("${primary}", primary, "quattro", uuid, "host", "token").is_err());
    }

    #[test]
    fn publish_replaces_stale_temporary_with_exact_mode() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = std::env::temp_dir().join(format!("mihomo-config-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("api.header");
        fs::write(dir.join("api.header.tmp"), "stale").unwrap();
        fs::write(&path, "old").unwrap();
        publish(&path, "new\n", 0o400, None).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "new\n");
        assert_eq!(fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o400);
        assert!(!dir.join("api.header.tmp").exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
