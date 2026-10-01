use anyhow::{Context, Result, anyhow, bail, ensure};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use std::{
    env,
    fs::{self, DirBuilder, File, Metadata, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};
use tokio::{net::TcpStream, time::timeout};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async_with_config,
    tungstenite::{Message, protocol::WebSocketConfig},
};

const PLUGIN_NAME: &str = "OpenDeck VTube Studio";
const PLUGIN_DEVELOPER: &str = "rikkichy";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const MESSAGE_LIMIT: usize = 1024 * 1024;
const AUTHORIZE_HINT: &str =
    "VTube Studio authorization is required. Open this action's settings and click Authorize.";
static TEMP_ID: AtomicU64 = AtomicU64::new(0);

unsafe extern "C" {
    fn geteuid() -> u32;
}

pub struct Client {
    directory: PathBuf,
    uid: u32,
}

pub struct Session {
    socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    next_id: u64,
}

impl Client {
    pub fn new() -> Result<Self> {
        let base = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| {
                env::var_os("HOME")
                    .map(PathBuf::from)
                    .filter(|path| path.is_absolute())
                    .map(|path| path.join(".local/share"))
            })
            .context("Set an absolute XDG_DATA_HOME or HOME to store VTube Studio credentials.")?;
        // SAFETY: geteuid takes no pointers and has no preconditions on Linux.
        let uid = unsafe { geteuid() };
        let directory = base.join("vts-opendeck");
        private_directory(&directory, uid)?;
        Ok(Self { directory, uid })
    }

    pub async fn connect(&self, port: u16, authorize: bool) -> Result<Session> {
        ensure!(
            port != 0,
            "The VTube Studio API port must be between 1 and 65535."
        );
        private_directory(&self.directory, self.uid)?;
        let path = self.directory.join(format!("{port}.token"));
        let cached = self.read_token(&path)?;
        ensure!(cached.is_some() || authorize, AUTHORIZE_HINT);
        let config = WebSocketConfig::default()
            .max_message_size(Some(MESSAGE_LIMIT))
            .max_frame_size(Some(MESSAGE_LIMIT))
            .max_write_buffer_size(MESSAGE_LIMIT * 2);
        let (socket, _) = timeout(
            Duration::from_secs(3),
            connect_async_with_config(format!("ws://127.0.0.1:{port}"), Some(config), false),
        )
        .await
        .map_err(|_| anyhow!("Connecting to VTube Studio timed out. Check the API port and enable Allow Plugin API access."))?
        .map_err(|_| anyhow!("Cannot connect to VTube Studio on loopback. Start VTube Studio, enable Allow Plugin API access, and check the API port."))?;
        let mut session = Session { socket, next_id: 0 };
        if let Some(token) = cached {
            if session.authenticate(&token).await? {
                return Ok(session);
            }
            ensure!(authorize, AUTHORIZE_HINT);
        }
        let data = session
            .exchange_with_timeout(
                "AuthenticationTokenRequest",
                json!({"pluginName": PLUGIN_NAME, "pluginDeveloper": PLUGIN_DEVELOPER}),
                Duration::from_secs(60),
            )
            .await?;
        let token = data["authenticationToken"]
            .as_str()
            .filter(|token| valid_token(token))
            .context("VTube Studio returned an invalid authentication token.")?;
        self.save_token(&path, token)?;
        ensure!(session.authenticate(token).await?, AUTHORIZE_HINT);
        Ok(session)
    }

    fn read_token(&self, path: &Path) -> Result<Option<String>> {
        let metadata = match fs::symlink_metadata(path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(_) => bail!("Cannot inspect the saved VTube Studio credential."),
        };
        private_file(&metadata, self.uid)?;
        let file = File::open(path).context("Cannot open the saved VTube Studio credential.")?;
        private_file(&file.metadata()?, self.uid)?;
        let mut token = String::new();
        file.take(65)
            .read_to_string(&mut token)
            .context("Cannot read the saved VTube Studio credential.")?;
        ensure!(
            valid_token(&token),
            "The saved VTube Studio credential is invalid. Remove the port's .token file from the vts-opendeck data directory, then click Authorize."
        );
        Ok(Some(token))
    }

    fn save_token(&self, path: &Path, token: &str) -> Result<()> {
        private_directory(&self.directory, self.uid)?;
        match fs::symlink_metadata(path) {
            Ok(metadata) => private_file(&metadata, self.uid)?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
            Err(_) => bail!("Cannot inspect the saved VTube Studio credential."),
        }
        let temporary = self.directory.join(format!(
            ".token-{}-{}",
            std::process::id(),
            TEMP_ID.fetch_add(1, Ordering::Relaxed)
        ));
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temporary)
            .context("Cannot create a private VTube Studio credential file.")?;
        let result = (|| -> Result<()> {
            private_file(&file.metadata()?, self.uid)?;
            file.write_all(token.as_bytes())?;
            file.sync_all()?;
            fs::rename(&temporary, path)?;
            File::open(&self.directory)?.sync_all()?;
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result.context("Cannot save the VTube Studio credential.")
    }
}

impl Session {
    pub async fn request(&mut self, kind: &str, data: Value) -> Result<Value> {
        self.exchange_with_timeout(kind, data, REQUEST_TIMEOUT)
            .await
    }

    async fn authenticate(&mut self, token: &str) -> Result<bool> {
        match self
            .request(
                "AuthenticationRequest",
                json!({
                    "pluginName": PLUGIN_NAME,
                    "pluginDeveloper": PLUGIN_DEVELOPER,
                    "authenticationToken": token,
                }),
            )
            .await
        {
            Ok(data) => data["authenticated"]
                .as_bool()
                .context("VTube Studio returned an invalid authentication response."),
            Err(error)
                if error
                    .downcast_ref::<ApiError>()
                    .is_some_and(|error| error.0 == 50) =>
            {
                Ok(false)
            }
            Err(error) => Err(error),
        }
    }

    async fn exchange_with_timeout(
        &mut self,
        kind: &str,
        data: Value,
        duration: Duration,
    ) -> Result<Value> {
        timeout(duration, self.exchange(kind, data))
            .await
            .map_err(|_| {
                if kind == "AuthenticationTokenRequest" {
                    anyhow!("VTube Studio authorization timed out. Click Authorize again and approve the request in VTube Studio.")
                } else {
                    anyhow!("VTube Studio did not respond within 5 seconds. The request was not retried.")
                }
            })?
    }

    async fn exchange(&mut self, kind: &str, data: Value) -> Result<Value> {
        let response_kind = format!(
            "{}Response",
            kind.strip_suffix("Request")
                .context("Invalid VTube Studio request type.")?
        );
        self.next_id = self
            .next_id
            .checked_add(1)
            .context("VTube Studio request ID exhausted.")?;
        let id = self.next_id.to_string();
        let payload = json!({
            "apiName": "VTubeStudioPublicAPI",
            "apiVersion": "1.0",
            "requestID": id,
            "messageType": kind,
            "data": data,
        });
        let text = serde_json::to_string(&payload)?;
        ensure!(
            text.len() <= MESSAGE_LIMIT,
            "VTube Studio request exceeds the message size limit."
        );
        timeout(
            REQUEST_TIMEOUT,
            self.socket.send(Message::Text(text.into())),
        )
        .await
        .map_err(|_| anyhow!("Sending to VTube Studio timed out. The request was not retried."))?
        .map_err(|_| anyhow!("Cannot send to VTube Studio. The request was not retried."))?;
        loop {
            let message = self.socket.next().await
                .context("VTube Studio closed the connection. The request was not retried.")?
                .map_err(|_| anyhow!("VTube Studio returned an invalid WebSocket message or disconnected. The request was not retried."))?;
            let text = match message {
                Message::Text(text) => text,
                Message::Ping(_) => {
                    // Tungstenite queues the matching pong when it reads a ping.
                    self.socket
                        .flush()
                        .await
                        .map_err(|_| anyhow!("Cannot respond to VTube Studio's ping."))?;
                    continue;
                }
                Message::Pong(_) => continue,
                Message::Close(_) => {
                    bail!("VTube Studio closed the connection. The request was not retried.")
                }
                _ => bail!("VTube Studio returned an unexpected non-text response."),
            };
            let mut response: Value = serde_json::from_str(&text)
                .map_err(|_| anyhow!("VTube Studio returned malformed JSON."))?;
            ensure!(
                response["apiName"] == "VTubeStudioPublicAPI"
                    && response["apiVersion"] == "1.0"
                    && response["requestID"].is_string()
                    && response["messageType"].is_string()
                    && response["data"].is_object(),
                "VTube Studio returned a malformed API response."
            );
            if response["requestID"] != id {
                continue;
            }
            if response["messageType"] == "APIError" {
                let code = response["data"]["errorID"]
                    .as_u64()
                    .context("VTube Studio returned a malformed API error.")?;
                return Err(ApiError(code).into());
            }
            ensure!(
                response["messageType"] == response_kind,
                "VTube Studio returned the wrong response type."
            );
            return Ok(response["data"].take());
        }
    }
}

#[derive(Debug)]
struct ApiError(u64);

impl std::fmt::Display for ApiError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.0 {
            1 => formatter.write_str("Enable Allow Plugin API access in VTube Studio."),
            8 | 50 => formatter.write_str("VTube Studio denied API access. Click Authorize in the action settings and approve access in VTube Studio."),
            51 => formatter.write_str("VTube Studio already has an authorization request open. Answer that request before clicking Authorize again."),
            _ => write!(formatter, "VTube Studio rejected the request (API error {}). The request was not retried.", self.0),
        }
    }
}

impl std::error::Error for ApiError {}

fn valid_token(token: &str) -> bool {
    !token.is_empty() && token.len() <= 64 && token.is_ascii()
}

fn private_file(metadata: &Metadata, uid: u32) -> Result<()> {
    ensure!(
        metadata.is_file()
            && metadata.uid() == uid
            && metadata.mode() & 0o777 == 0o600
            && metadata.nlink() == 1,
        "The VTube Studio credential must be a regular, non-linked file owned by the current user with mode 0600."
    );
    Ok(())
}

fn private_directory(directory: &Path, uid: u32) -> Result<()> {
    // HOME/XDG_DATA_HOME belongs to the launching process and may itself be symlinked.
    // Only our private storage directory must not be a link.
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)
        .context("Cannot create the VTube Studio credential directory.")?;
    let metadata = fs::symlink_metadata(directory)
        .context("Cannot inspect the VTube Studio credential directory.")?;
    ensure!(
        metadata.is_dir() && metadata.uid() == uid && metadata.mode() & 0o777 == 0o700,
        "The VTube Studio credential directory must be a non-linked directory owned by the current user with mode 0700."
    );
    Ok(())
}
