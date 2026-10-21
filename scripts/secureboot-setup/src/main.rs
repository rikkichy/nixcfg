use serde::Deserialize;
use std::collections::HashSet;
use std::ffi::OsString;
#[cfg(target_os = "linux")]
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, IsTerminal, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const EFI: &str = "/sys/firmware/efi/efivars";
const STATE: &str = "/var/lib/sbctl";
const BACKUP: &str = "/var/lib/sbctl/before-enrollment";
const IMAGE: &str = "/boot/efi/limine/BOOTX64.EFI";
const CONFIG: &str = "/boot/limine/limine.conf";
const X509: [u8; 16] = [0xa1, 0x59, 0xc0, 0xa5, 0xe4, 0x94, 0xa7, 0x4a, 0x87, 0xb5, 0xab, 0x15, 0x5c, 0x2b, 0xf0, 0x72];
const SHA256: [u8; 16] = [0x26, 0x16, 0xc4, 0xc1, 0x4c, 0x50, 0x92, 0x40, 0xac, 0xa9, 0x41, 0xf9, 0x36, 0x93, 0x43, 0x28];
type Result<T, E = Box<dyn std::error::Error>> = std::result::Result<T, E>;

#[derive(Debug)]
struct Stopped;
impl std::fmt::Display for Stopped {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str("Stopped") }
}
impl std::error::Error for Stopped {}

struct Session { signal: Arc<AtomicUsize> }
impl Session {
    fn interrupted(&self) -> Result<()> {
        let signal = self.signal.load(Ordering::SeqCst);
        if signal != 0 { return Err(format!("Interrupted by signal {signal}").into()); }
        Ok(())
    }

    fn run(&self, command: &mut Command, capture: bool) -> Result<Vec<u8>> {
        self.command(command, capture, false)
    }

    fn command(&self, command: &mut Command, capture: bool, cleanup: bool) -> Result<Vec<u8>> {
        if !cleanup { self.interrupted()?; }
        // A temporary file avoids pipe deadlocks while we wait for signals. It is
        // unlinked immediately and contains only public command output.
        let mut output = if capture { Some(tempfile::tempfile()?) } else { None };
        if let Some(file) = &output { command.stdout(Stdio::from(file.try_clone()?)); }
        if cleanup {
            // A second terminal signal must not kill chattr while restoring flags.
            unsafe {
                command.pre_exec(|| {
                    let mut mask = std::mem::zeroed();
                    libc::sigemptyset(&mut mask);
                    for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] { libc::sigaddset(&mut mask, signal); }
                    if libc::sigprocmask(libc::SIG_BLOCK, &mask, std::ptr::null_mut()) != 0 { return Err(io::Error::last_os_error()); }
                    Ok(())
                });
            }
        }
        let mut child = command.spawn()?;
        let mut forwarded = false;
        let status = loop {
            if let Some(status) = child.try_wait()? { break status; }
            let signal = self.signal.load(Ordering::SeqCst);
            if !cleanup && signal != 0 && !forwarded {
                // Wait for the writer to exit before restoring immutable flags.
                unsafe { libc::kill(child.id() as libc::pid_t, signal as libc::c_int); }
                forwarded = true;
            }
            thread::sleep(Duration::from_millis(50));
        };
        if !cleanup { self.interrupted()?; }
        if !status.success() { return Err(format!("{} failed: {status}", command.get_program().to_string_lossy()).into()); }
        let mut bytes = Vec::new();
        if let Some(file) = &mut output {
            use std::io::{Seek, SeekFrom};
            file.seek(SeekFrom::Start(0))?;
            file.read_to_end(&mut bytes)?;
        }
        Ok(bytes)
    }

    fn confirm(&self, message: &str) -> Result<()> {
        self.interrupted()?;
        print!("{message} [y/N]: ");
        io::stdout().flush()?;
        let mut answer = Vec::new();
        loop {
            self.interrupted()?;
            let mut descriptor = libc::pollfd { fd: libc::STDIN_FILENO, events: libc::POLLIN, revents: 0 };
            let ready = unsafe { libc::poll(&mut descriptor, 1, 100) };
            if ready < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted { continue; }
                return Err(error.into());
            }
            if ready == 0 { continue; }
            // Read the polled descriptor directly, without a buffered stdin reader.
            let mut byte = 0u8;
            let count = unsafe { libc::read(libc::STDIN_FILENO, (&mut byte as *mut u8).cast(), 1) };
            if count < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted { continue; }
                return Err(error.into());
            }
            if count == 0 { return Err("End of input while waiting for approval".into()); }
            if byte == b'\n' { break; }
            answer.push(byte);
        }
        self.interrupted()?;
        if !matches!(String::from_utf8(answer)?.trim().to_ascii_lowercase().as_str(), "y" | "yes") {
            println!("Stopped. Rerun the same command to resume; nothing is reset.");
            return Err(Stopped.into());
        }
        Ok(())
    }
}

fn variable(name: &str, directory: &Path) -> Result<Option<PathBuf>> {
    let prefix = format!("{name}-");
    let mut found = None;
    for item in fs::read_dir(directory)? {
        let path = item?.path();
        let filename = path.file_name().unwrap().to_string_lossy();
        if filename.starts_with(&prefix) && !filename.ends_with(".esl") {
            if found.is_some() { return Err(format!("Ambiguous EFI variable: {name}").into()); }
            found = Some(path);
        }
    }
    Ok(found)
}

fn value(name: &str, directory: &Path) -> Result<Vec<u8>> {
    match variable(name, directory)? {
        None => Ok(Vec::new()),
        Some(path) => {
            let mut data = fs::read(path)?;
            if data.len() < 4 { return Err(format!("Truncated EFI variable: {name}").into()); }
            data.drain(..4);
            Ok(data)
        }
    }
}
fn firmware(name: &str) -> Result<Vec<u8>> { value(name, Path::new(EFI)) }

#[derive(Hash, PartialEq, Eq)]
struct Entry<'a> { kind: &'a [u8], owner: &'a [u8], data: &'a [u8] }

// Compare lists independently of order, but retain the signature owner GUID.
fn entries(data: &[u8]) -> Result<HashSet<Entry<'_>>> {
    let mut result = HashSet::new();
    let mut offset = 0;
    while offset < data.len() {
        let remaining = &data[offset..];
        if remaining.len() < 28 { return Err("Truncated EFI signature list".into()); }
        let size = u32::from_le_bytes(remaining[16..20].try_into()?) as usize;
        let header = u32::from_le_bytes(remaining[20..24].try_into()?) as usize;
        let width = u32::from_le_bytes(remaining[24..28].try_into()?) as usize;
        let start = 28usize.checked_add(header).ok_or("Malformed EFI signature list")?;
        if size < start || width < 16 || size > remaining.len() || (size - start) % width != 0 {
            return Err("Malformed EFI signature list".into());
        }
        for signature in remaining[start..size].chunks_exact(width) {
            result.insert(Entry { kind: &remaining[..16], owner: &signature[..16], data: &signature[16..] });
        }
        offset += size;
    }
    Ok(result)
}

fn root_owned(path: &Path, private: bool) -> Result<()> {
    for item in path.ancestors() {
        let info = match fs::symlink_metadata(item) {
            Ok(info) => info,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };
        if info.file_type().is_symlink() || info.uid() != 0 || info.mode() & 0o022 != 0 {
            return Err(format!("Unsafe ownership, permissions or symlink: {}", item.display()).into());
        }
    }
    if private && fs::metadata(path)?.mode() & 0o077 != 0 {
        return Err(format!("Private key is accessible to other users: {}", path.display()).into());
    }
    Ok(())
}

fn certificate(session: &Session, name: &str) -> Result<Vec<u8>> {
    session.run(Command::new("openssl").args(["x509", "-in"]).arg(Path::new(STATE).join("keys").join(name).join(format!("{name}.pem"))).args(["-outform", "DER"]), true)
}
fn local_key_present(session: &Session, name: &str) -> Result<bool> {
    let cert = certificate(session, name)?;
    Ok(entries(&firmware(name)?)?.iter().any(|entry| entry.kind == X509 && entry.data == cert))
}
fn check_keys(session: &Session) -> Result<()> {
    for name in ["PK", "KEK", "db"] {
        let key = Path::new(STATE).join("keys").join(name).join(format!("{name}.key"));
        let cert = key.with_extension("pem");
        if !key.is_file() || !cert.is_file() { return Err("Incomplete key set: restore existing keys; do not regenerate them".into()); }
        root_owned(&key, true)?;
        root_owned(&cert, false)?;
        let public = session.run(Command::new("openssl").args(["pkey", "-in"]).arg(&key).arg("-pubout"), true)?;
        if public != session.run(Command::new("openssl").args(["x509", "-in"]).arg(&cert).args(["-pubkey", "-noout"]), true)? {
            return Err(format!("{name}: private key and certificate do not match").into());
        }
    }
    Ok(())
}

fn write_backup(path: &Path, data: &[u8]) -> Result<()> {
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(path)?;
    file.write_all(data)?;
    file.sync_all()?;
    Ok(())
}

fn publish_backup(source: &Path, destination: &Path) -> Result<()> {
    // Never replace even an empty pre-existing backup directory.
    #[cfg(target_os = "linux")]
    {
        let source = CString::new(source.as_os_str().as_bytes())?;
        let destination = CString::new(destination.as_os_str().as_bytes())?;
        if unsafe { libc::renameat2(libc::AT_FDCWD, source.as_ptr(), libc::AT_FDCWD, destination.as_ptr(), libc::RENAME_NOREPLACE) } != 0 {
            return Err(io::Error::last_os_error().into());
        }
        Ok(())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (source, destination);
        Err("Backup publication requires installed Linux".into())
    }
}

fn backup(session: &Session) -> Result<()> {
    let backup = Path::new(BACKUP);
    root_owned(backup, false)?;
    let directory = if backup.exists() { backup } else { Path::new(EFI) };
    for name in ["KEK", "db"] {
        if variable(name, directory)?.is_none() { return Err("Missing original KEK/db snapshot; review vendor trust before setup".into()); }
    }
    if backup.exists() {
        if !backup.join("BOOTX64.EFI").is_file() || !backup.join("limine.conf").is_file() { return Err("Incomplete existing backup; inspect it instead of replacing it".into()); }
        println!("Preserving existing backup: {BACKUP}");
        return Ok(());
    }
    let temporary = tempfile::Builder::new().prefix(".secureboot-backup-").tempdir_in(STATE)?;
    let databases = ["PK", "KEK", "db", "dbx", "dbt", "dbr", "PKDefault", "KEKDefault", "dbDefault", "dbxDefault"];
    for name in databases.iter().copied().chain(["SecureBoot", "SetupMode"]) {
        session.interrupted()?;
        if let Some(source) = variable(name, Path::new(EFI))? {
            let raw = fs::read(&source)?;
            if raw.len() < 4 { return Err(format!("Truncated EFI variable: {name}").into()); }
            write_backup(&temporary.path().join(source.file_name().unwrap()), &raw)?;
            if databases.contains(&name) {
                entries(&raw[4..])?;
                let mut filename = source.file_name().unwrap().to_os_string();
                filename.push(".esl");
                write_backup(&temporary.path().join(filename), &raw[4..])?;
            }
        }
    }
    for source in [Path::new(IMAGE), Path::new(CONFIG)] {
        write_backup(&temporary.path().join(source.file_name().unwrap()), &fs::read(source)?)?;
    }
    File::open(temporary.path())?.sync_all()?;
    session.interrupted()?;
    publish_backup(temporary.path(), backup)?;
    File::open(STATE)?.sync_all()?;
    println!("Saved public firmware databases and boot files: {BACKUP}");
    Ok(())
}

fn check_preserved(original: &[(&str, Vec<u8>)]) -> Result<()> {
    for (name, data) in original {
        if !entries(data)?.is_subset(&entries(&firmware(name)?)?) {
            return Err(format!("{name}: original trust entries were lost; stop and inspect").into());
        }
    }
    Ok(())
}

#[derive(Deserialize)]
struct EventLog { events: Vec<Event> }
#[derive(Deserialize)]
struct Event {
    #[serde(rename = "EventType")]
    event_type: Option<String>,
    #[serde(rename = "Digests")]
    digests: Option<Vec<Digest>>,
}
#[derive(Deserialize)]
struct Digest {
    #[serde(rename = "AlgorithmId")]
    algorithm: String,
    #[serde(rename = "Digest")]
    digest: String,
}
fn sha256(text: &str) -> Result<[u8; 32]> {
    if text.len() != 64 || !text.bytes().all(|byte| byte.is_ascii_hexdigit()) { return Err("Malformed SHA-256 digest".into()); }
    let mut bytes = [0; 32];
    for (index, byte) in bytes.iter_mut().enumerate() { *byte = u8::from_str_radix(&text[index * 2..index * 2 + 2], 16)?; }
    Ok(bytes)
}
fn check_eventlog(yaml: &[u8], revoked: &HashSet<&[u8]>) -> Result<()> {
    let log: EventLog = serde_saphyr::from_slice(yaml)?;
    let mut checked = 0;
    for event in log.events {
        if !matches!(event.event_type.as_deref(), Some("EV_EFI_BOOT_SERVICES_APPLICATION" | "EV_EFI_BOOT_SERVICES_DRIVER" | "EV_EFI_RUNTIME_SERVICES_DRIVER")) { continue; }
        for digest in event.digests.ok_or("Measured EFI image has no digest list")? {
            if digest.algorithm == "sha256" {
                let hash = sha256(&digest.digest)?;
                checked += 1;
                if revoked.contains(hash.as_slice()) { return Err("A measured EFI image is revoked by the factory dbx".into()); }
            }
        }
    }
    if checked == 0 { return Err("No measured EFI image hashes available; review dbx manually".into()); }
    Ok(())
}

fn setup_mode(setup: &[u8], pk: &[u8], secure_boot: &[u8]) -> Result<()> {
    if setup != [1] || !pk.is_empty() || secure_boot != [0] {
        return Err("Operation requires Setup Mode, no PK, and Secure Boot disabled".into());
    }
    Ok(())
}
fn restore_dbx(session: &Session) -> Result<()> {
    let dbx = firmware("dbx")?;
    if !dbx.is_empty() { entries(&dbx)?; return Ok(()); }
    setup_mode(&firmware("SetupMode")?, &firmware("PK")?, &firmware("SecureBoot")?)?;
    let factory = firmware("dbxDefault")?;
    let revocations = entries(&factory)?;
    // ponytail: SHA-256 factory lists only; other types need certificate-revocation checks.
    if revocations.is_empty() || revocations.iter().any(|entry| entry.kind != SHA256 || entry.data.len() != 32) {
        return Err("Missing or unsupported factory dbx; review revocations manually".into());
    }
    if factory != value("dbxDefault", Path::new(BACKUP))? { return Err("Factory dbx changed since backup; review before restoring".into()); }
    let revoked: HashSet<&[u8]> = revocations.iter().map(|entry| entry.data).collect();
    let output = session.run(Command::new("pesign").args(["--hash", "--digest-type", "sha256", "--in", IMAGE]), true)?;
    let output = std::str::from_utf8(&output)?;
    let mut digests = output.split(|ch: char| ch.is_whitespace() || (!ch.is_alphanumeric() && ch != '_'))
        .filter(|word| word.len() == 64 && word.bytes().all(|byte| byte.is_ascii_hexdigit()));
    let hash = digests.next().ok_or("Limine Authenticode digest is unavailable or revoked")?;
    if digests.next().is_some() || revoked.contains(sha256(hash)?.as_slice()) { return Err("Limine Authenticode digest is unavailable or revoked".into()); }
    check_eventlog(&session.run(Command::new("tpm2_eventlog").arg("/sys/kernel/security/tpm0/binary_bios_measurements"), true)?, &revoked)?;
    session.confirm(&format!("Restore missing dbx with {} checked factory revocations (not necessarily the latest updates)?", revocations.len()))?;
    let temporary = tempfile::Builder::new().prefix("nixcfg-dbx-").tempdir_in("/run")?;
    let esl = temporary.path().join("dbx.esl");
    write_backup(&esl, &factory)?;
    session.run(Command::new("efi-updatevar").args(["-e", "-f"]).arg(esl).arg("dbx"), false)?;
    if firmware("dbx")? != factory { return Err("dbx write verification failed; do not retry blindly".into()); }
    Ok(())
}

struct ImmutableGuard<'a> { session: &'a Session, paths: Vec<PathBuf> }
impl ImmutableGuard<'_> {
    fn restore(&mut self) -> Result<()> {
        let mut errors = Vec::new();
        while let Some(path) = self.paths.pop() {
            if let Err(error) = self.session.command(Command::new("chattr").arg("+i").arg(&path), false, true) {
                errors.push(format!("{}: {error}", path.display()));
            }
        }
        if !errors.is_empty() { return Err(format!("Failed to restore immutable flags: {}", errors.join("; ")).into()); }
        Ok(())
    }
}
impl Drop for ImmutableGuard<'_> {
    fn drop(&mut self) {
        if let Err(error) = self.restore() { eprintln!("ERROR: {error}. Restore the listed flags before retrying."); }
    }
}
fn immutable(session: &Session, path: &Path) -> Result<bool> {
    let output = session.run(Command::new("lsattr").arg("-d").arg(path), true)?;
    let attributes = std::str::from_utf8(&output)?.split_whitespace().next().ok_or("Empty lsattr output")?;
    Ok(attributes.contains('i'))
}
fn enroll(session: &Session) -> Result<()> {
    setup_mode(&firmware("SetupMode")?, &firmware("PK")?, &firmware("SecureBoot")?)?;
    let original = [ ("KEK", value("KEK", Path::new(BACKUP))?), ("db", value("db", Path::new(BACKUP))?) ];
    check_preserved(&original)?;
    let before = [("KEK", firmware("KEK")?), ("db", firmware("db")?)];
    let dbx = firmware("dbx")?;
    if dbx.is_empty() { return Err("Revocation database is missing".into()); }
    let mut locked = Vec::new();
    for name in ["KEK", "db"] {
        if let Some(path) = variable(name, Path::new(EFI))? {
            if immutable(session, &path)? { locked.push(path); }
        }
    }
    let unlock = if locked.is_empty() { "none".to_owned() } else {
        locked.iter().map(|path| path.file_name().unwrap().to_string_lossy().split('-').next().unwrap().to_owned()).collect::<Vec<_>>().join(", ")
    };
    session.confirm(&format!("Enroll local keys, appending Microsoft/OEM trust; temporarily unlock immutable variables: {unlock}?"))?;
    let mut restore = ImmutableGuard { session, paths: Vec::new() };
    for path in &locked {
        // Register before invoking chattr: interruption can follow a successful write.
        restore.paths.push(path.clone());
        session.run(Command::new("chattr").arg("-i").arg(path), false)?;
    }
    let enrollment = session.run(Command::new("sbctl").args(["enroll-keys", "--append", "--microsoft", "--firmware-builtin=db,KEK"]), false);
    restore.restore()?;
    enrollment?;
    check_preserved(&before)?;
    if firmware("dbx")? != dbx || firmware("SetupMode")? != [0] {
        return Err("Enrollment verification failed; inspect firmware databases before proceeding".into());
    }
    for name in ["PK", "KEK", "db"] {
        if !local_key_present(session, name)? { return Err("Enrollment verification failed; inspect firmware databases before proceeding".into()); }
    }
    for path in &locked {
        if !immutable(session, path)? { return Err(format!("Immutable flag was not restored: {}", path.display()).into()); }
    }
    Ok(())
}

fn activate(session: &Session, repository: &Path) -> Result<()> {
    session.confirm("Activate the reviewed checkout with nh os switch and update signed EFI boot files?")?;
    let mut flake = OsString::from("path:");
    flake.push(repository);
    session.run(Command::new("nh").args(["os", "switch", "--bypass-root-check", "--no-nom", "--hostname", "nix"]).arg(flake), false)?;
    Ok(())
}
fn firmware_step(enrolled: bool) {
    if enrolled {
        println!("Keys are enrolled. In BIOS: keep Custom mode, enable Secure Boot, and select Maximum Security / Deny Execute. Do not restore factory keys.");
    } else {
        println!("Limine installation completed without a post-install hash/signature check. In BIOS: remove ONLY PK to enter Setup Mode, retaining KEK/db/dbx. Keep Secure Boot disabled.");
        println!("MSI: Reset To Setup Mode deletes ALL keys. If no explicit PK-only action exists, stop rather than using it.");
        println!("Keep a working recovery ISO/console, LUKS passphrase and encrypted offline key backup before changing firmware.");
    }
    println!("No reboot was performed. Rerun this command after the BIOS step. Recovery: disable enforcement without deleting keys.");
}

fn workflow(session: &Session, repository: &Path, status: bool) -> Result<()> {
    if unsafe { libc::geteuid() } != 0 || !Path::new("/etc/NIXOS").exists() || !Path::new(EFI).is_dir() {
        return Err("Run on the installed NixOS desktop in UEFI mode with sudo".into());
    }
    session.run(&mut Command::new("sbctl").arg("status"), false)?;
    if status { return Ok(()); }
    let mut hostname = [0u8; 256];
    if unsafe { libc::gethostname(hostname.as_mut_ptr().cast(), hostname.len()) } != 0 { return Err(io::Error::last_os_error().into()); }
    if hostname.split(|byte| *byte == 0).next() != Some(b"nix".as_slice()) {
        return Err("This helper activates the repository desktop host nix, not other hosts".into());
    }
    if Path::new("/etc/sbctl/sbctl.conf").exists() { return Err("Custom sbctl configuration requires separate review; this helper uses the standard key paths".into()); }
    if !io::stdin().is_terminal() { return Err("Interactive terminal required; use --status for read-only checks".into()); }
    if !Path::new(IMAGE).is_file() || !Path::new(CONFIG).is_file() { return Err("Expected the installed x86_64 Limine boot files under /boot".into()); }
    let repository = fs::canonicalize(repository)?;
    root_owned(Path::new(STATE), false)?;
    if repository.starts_with(STATE) || Path::new(STATE).starts_with(&repository) { return Err("The checkout must not contain or reside in the private signing directory".into()); }
    if !repository.join(".git").exists() || !repository.join("flake.nix").is_file() || !repository.join("hosts/nix/boot.nix").is_file() {
        return Err("Expected a reviewed Git checkout of this repository, not an arbitrary directory".into());
    }
    let mut attribute = OsString::from("path:");
    attribute.push(&repository);
    attribute.push("#nixosConfigurations.nix.config.boot.loader.limine.secureBoot.enable");
    let enabled = session.run(Command::new("nix").args(["eval", "--json"]).arg(attribute), true)?;
    if std::str::from_utf8(&enabled)?.trim() != "true" { return Err("This checkout must enable native Limine Secure Boot for host nix".into()); }
    if !Path::new(STATE).join("keys").exists() {
        if Path::new(STATE).exists() && fs::read_dir(STATE)?.next().transpose()?.is_some() {
            return Err("sbctl state exists without keys; restore it instead of creating a new identity".into());
        }
        session.confirm("Create local PK/KEK/db signing keys under root-only /var/lib/sbctl?")?;
        match fs::create_dir(STATE) {
            Ok(()) => (),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => (),
            Err(error) => return Err(error.into()),
        }
        session.run(Command::new("sbctl").arg("create-keys"), false)?;
        fs::set_permissions(STATE, fs::Permissions::from_mode(0o700))?;
    }
    check_keys(session)?;
    uuid::Uuid::parse_str(fs::read_to_string(Path::new(STATE).join("GUID"))?.trim())?;
    backup(session)?;
    activate(session, &repository)?;
    if local_key_present(session, "PK")? {
        if !local_key_present(session, "KEK")? || !local_key_present(session, "db")? || firmware("dbx")?.is_empty() {
            return Err("Local PK is enrolled but trust/revocations are incomplete; inspect before further writes".into());
        }
        if firmware("SecureBoot")? == [1] {
            println!("Secure Boot is enabled; local keys are enrolled. Installed Limine was not verified. Still confirm MSI Maximum Security / Deny Execute in BIOS.");
        } else { firmware_step(true); }
        return Ok(());
    }
    if firmware("SetupMode")? != [1] { firmware_step(false); return Ok(()); }
    session.confirm("Confirm a working recovery ISO/console, LUKS passphrase, and a protected offline backup of /var/lib/sbctl before firmware writes?")?;
    restore_dbx(session)?;
    enroll(session)?;
    firmware_step(true);
    Ok(())
}

const HELP: &str = "usage: nixcfg-secureboot-setup [-h] [--status] [repository]\n\nGuided setup for this repository's installed NixOS/Limine desktop.\n\npositional arguments:\n  repository  reviewed checkout (default: /etc/nixos)\n\noptions:\n  -h, --help  show this help message and exit\n  --status    read-only Secure Boot status\n\nUses native sbctl. No key rotation, automatic PK deletion, firmware enforcement\ntoggle or reboot. Rerun after each BIOS step.";
fn arguments() -> Result<Option<(PathBuf, bool)>> {
    let mut repository = None;
    let mut status = false;
    let mut positional = false;
    for argument in std::env::args_os().skip(1) {
        if !positional {
            if argument == "--help" || argument == "-h" { println!("{HELP}"); return Ok(None); }
            if argument == "--status" { status = true; continue; }
            if argument == "--" { positional = true; continue; }
            if argument.as_bytes().starts_with(b"-") && argument != "-" { return Err(format!("unrecognized argument: {}", argument.to_string_lossy()).into()); }
        }
        if repository.replace(PathBuf::from(argument)).is_some() { return Err("only one repository argument is accepted".into()); }
    }
    Ok(Some((repository.unwrap_or_else(|| PathBuf::from("/etc/nixos")), status)))
}
fn lock_session() -> Result<File> {
    let path = Path::new("/run/nixcfg-secureboot.lock");
    root_owned(path, false)?;
    let file = OpenOptions::new().write(true).create(true).truncate(false).mode(0o600).custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC).open(path)?;
    let info = file.metadata()?;
    if !info.is_file() || info.uid() != 0 || info.mode() & 0o022 != 0 { return Err("Unsafe enrollment lock file".into()); }
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 { return Err(io::Error::last_os_error().into()); }
    Ok(file)
}
fn main() {
    let (repository, status) = match arguments() {
        Ok(Some(arguments)) => arguments,
        Ok(None) => return,
        Err(error) => { eprintln!("nixcfg-secureboot-setup: {error}\n{HELP}"); std::process::exit(2); }
    };
    unsafe { libc::umask(0o077); }
    let session = Session { signal: Arc::new(AtomicUsize::new(0)) };
    let result = (|| -> Result<()> {
        for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
            signal_hook::flag::register_usize(signal, Arc::clone(&session.signal), signal as usize)?;
        }
        // Status/help do not create lock files. Keep the lock through cleanup.
        let _lock = if status { None } else { Some(lock_session()?) };
        workflow(&session, &repository, status)
    })();
    if let Err(error) = result {
        if error.downcast_ref::<Stopped>().is_some() { return; }
        eprintln!("ERROR: {error}\nStopped. Inspect any completed writes before retrying; keys were not reset or rotated.");
        let signal = session.signal.load(Ordering::SeqCst);
        std::process::exit(if signal == 0 || signal == libc::SIGINT as usize { 1 } else { 128 + signal as i32 });
    }
}
