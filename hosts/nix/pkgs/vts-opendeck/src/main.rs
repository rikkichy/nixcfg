mod vts;

use anyhow::{Context, Result, bail, ensure};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{Value, json};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio_tungstenite::{
    connect_async_with_config,
    tungstenite::{Message, protocol::WebSocketConfig},
};

const HOTKEY: &str = "com.rikkichy.vtubestudio.hotkey";
const MODEL: &str = "com.rikkichy.vtubestudio.model";

#[derive(Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct Settings {
    port: u16,
    #[serde(rename = "modelID")]
    model_id: String,
    #[serde(rename = "hotkeyID")]
    hotkey_id: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            port: 8001,
            model_id: String::new(),
            hotkey_id: String::new(),
        }
    }
}

struct Job {
    event: Value,
    received: Instant,
}

async fn execute(client: &vts::Client, event: &Value) -> Result<Value> {
    let action = event["action"].as_str().context("Missing action")?;
    ensure!(matches!(action, HOTKEY | MODEL), "Unknown action");
    let settings: Settings = serde_json::from_value(event["payload"]["settings"].clone())
        .context("Invalid action settings")?;
    ensure!(settings.port != 0, "API port must be between 1 and 65535");
    ensure!(
        settings.model_id.len() <= 128 && settings.hotkey_id.len() <= 128,
        "Invalid model or hotkey ID"
    );

    let inspector = event["event"] == "sendToPlugin";
    let authorize = if inspector {
        match event["payload"]["command"].as_str() {
            Some("authorize") => true,
            Some("refresh") => false,
            _ => bail!("Unknown inspector command"),
        }
    } else {
        if action == MODEL {
            ensure!(
                !settings.model_id.is_empty(),
                "Choose a model in this button's settings"
            );
        } else {
            ensure!(
                !settings.hotkey_id.is_empty(),
                "Choose a hotkey in this button's settings"
            );
        }
        false
    };
    let mut session = client.connect(settings.port, authorize).await?;
    if inspector {
        let models = session.request("AvailableModelsRequest", json!({})).await?;
        let hotkeys = if action == HOTKEY {
            let data = if settings.model_id.is_empty() {
                json!({})
            } else {
                json!({"modelID":settings.model_id})
            };
            session
                .request("HotkeysInCurrentModelRequest", data)
                .await?
        } else {
            json!({"availableHotkeys":[], "modelName":""})
        };
        return Ok(json!({
            "models": models["availableModels"],
            "hotkeys": hotkeys["availableHotkeys"],
            "modelName": hotkeys["modelName"],
        }));
    }
    if action == MODEL {
        session
            .request("ModelLoadRequest", json!({"modelID":settings.model_id}))
            .await?;
    } else {
        if !settings.model_id.is_empty() {
            let current = session.request("CurrentModelRequest", json!({})).await?;
            ensure!(
                current["modelLoaded"] == true && current["modelID"] == settings.model_id,
                "The hotkey's model is not loaded; switch models first"
            );
        }
        session
            .request(
                "HotkeyTriggerRequest",
                json!({"hotkeyID":settings.hotkey_id}),
            )
            .await?;
    }
    Ok(json!({}))
}

fn reply(event: &Value, result: Result<Value>) -> Vec<Value> {
    let context = &event["context"];
    let inspector = event["event"] == "sendToPlugin";
    match result {
        Ok(mut data) if inspector => {
            data["ok"] = json!(true);
            data["requestId"] = event["payload"]["requestId"].clone();
            vec![json!({"event":"sendToPropertyInspector", "context":context, "payload":data})]
        }
        Ok(_) => vec![json!({"event":"showOk", "context":context})],
        Err(error) => {
            let error = format!("{error:#}");
            eprintln!("VTube Studio: {error}");
            let mut messages = vec![json!({
                "event":"sendToPropertyInspector", "context":context,
                "payload":{"ok":false, "error":error, "requestId":event["payload"]["requestId"]},
            })];
            if !inspector {
                messages.push(json!({"event":"showAlert", "context":context}));
            }
            messages
        }
    }
}

fn launch_options() -> Result<(u16, String)> {
    let mut args = std::env::args().skip(1);
    let (mut port, mut uuid, mut registration) = (None, None, None);
    while let Some(key) = args.next() {
        let value = args
            .next()
            .context("OpenDeck launch arguments require values")?;
        match key.as_str() {
            "-port" => port = Some(value.parse::<u16>().context("Invalid OpenDeck port")?),
            "-pluginUUID" => uuid = Some(value),
            "-registerEvent" => registration = Some(value),
            "-info" => {}
            _ => bail!("Unknown launch argument"),
        }
    }
    ensure!(
        registration.as_deref() == Some("registerPlugin"),
        "Launch this plugin from OpenDeck"
    );
    let port = port.context("Missing OpenDeck port")?;
    ensure!(port != 0, "Invalid OpenDeck port");
    Ok((port, uuid.context("Missing plugin UUID")?))
}

#[tokio::main]
async fn main() -> Result<()> {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("vts-opendeck {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let (port, uuid) = launch_options()?;
    let client = vts::Client::new()?;
    let config = WebSocketConfig::default()
        .max_message_size(Some(1024 * 1024))
        .max_frame_size(Some(1024 * 1024));
    let (mut socket, _) = tokio::time::timeout(
        Duration::from_secs(3),
        connect_async_with_config(format!("ws://127.0.0.1:{port}"), Some(config), false),
    )
    .await
    .context("OpenDeck connection timed out")??;
    socket
        .send(Message::Text(
            json!({"event":"registerPlugin", "uuid":uuid})
                .to_string()
                .into(),
        ))
        .await?;

    let (jobs_tx, mut jobs_rx) = mpsc::channel::<Job>(16);
    let (output_tx, mut output_rx) = mpsc::channel::<Value>(32);
    let worker = tokio::spawn(async move {
        while let Some(job) = jobs_rx.recv().await {
            // Do not fire old expressions after an authorization dialog or stalled API.
            let result = if job.event["event"] == "keyDown"
                && job.received.elapsed() > Duration::from_secs(3)
            {
                Err(anyhow::anyhow!(
                    "Button press expired while VTube Studio was busy; press again"
                ))
            } else {
                execute(&client, &job.event).await
            };
            for message in reply(&job.event, result) {
                if output_tx.send(message).await.is_err() {
                    return;
                }
            }
        }
    });
    let result = async {
        loop {
            tokio::select! {
                frame = socket.next() => {
                    match frame {
                        Some(Ok(Message::Text(text))) => {
                            let event: Value = match serde_json::from_str(&text) {
                                Ok(event) => event,
                                Err(_) => { eprintln!("Ignoring malformed OpenDeck event"); continue; }
                            };
                            if !matches!(event["event"].as_str(), Some("keyDown" | "sendToPlugin")) { continue; }
                            if event["context"].is_null() { continue; }
                            if let Err(error) = jobs_tx.try_send(Job { event, received: Instant::now() }) {
                                for message in reply(&error.into_inner().event, Err(anyhow::anyhow!("VTube Studio is busy; try again"))) {
                                    socket.send(Message::Text(message.to_string().into())).await?;
                                }
                            }
                        },
                        Some(Ok(Message::Ping(_))) => socket.flush().await?,
                        Some(Ok(Message::Close(_))) | None => break,
                        Some(Err(error)) => return Err(error.into()),
                        _ => {},
                    }
                },
                message = output_rx.recv() => {
                    let Some(message) = message else { bail!("VTube Studio worker stopped"); };
                    socket.send(Message::Text(message.to_string().into())).await?;
                },
            }
        }
        Ok(())
    }.await;
    worker.abort();
    result
}
