use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use std::{
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::Mutex,
};
use tokio_tungstenite::{WebSocketStream, accept_async, tungstenite::Message};

const HOTKEY: &str = "com.rikkichy.vtubestudio.hotkey";
const MODEL: &str = "com.rikkichy.vtubestudio.model";

struct Runtime {
    child: Child,
    directory: PathBuf,
}
impl Drop for Runtime {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

#[derive(Default)]
struct VtsState {
    allow: bool,
    revoke: bool,
    model: String,
    effects: Vec<String>,
    token_requests: usize,
    drop_trigger_reply: bool,
}

async fn receive(socket: &mut WebSocketStream<TcpStream>) -> Value {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            match socket.next().await.unwrap().unwrap() {
                Message::Text(text) => return serde_json::from_str(&text).unwrap(),
                Message::Ping(_) => socket.flush().await.unwrap(),
                frame => panic!("Unexpected frame: {frame:?}"),
            }
        }
    })
    .await
    .expect("Protocol response timed out")
}

async fn send(socket: &mut WebSocketStream<TcpStream>, value: Value) {
    socket
        .send(Message::Text(value.to_string().into()))
        .await
        .unwrap();
}

async fn mock_vts(stream: TcpStream, state: Arc<Mutex<VtsState>>) {
    let Ok(mut socket) = accept_async(stream).await else {
        return;
    };
    let mut authenticated = false;
    while let Some(Ok(Message::Text(text))) = socket.next().await {
        let request: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(request["apiName"], "VTubeStudioPublicAPI");
        assert_eq!(request["apiVersion"], "1.0");
        let kind = request["messageType"].as_str().unwrap();
        let (response_type, data, disconnect) = {
            let mut state = state.lock().await;
            let data = match kind {
                "AuthenticationTokenRequest" => {
                    state.token_requests += 1;
                    if state.allow {
                        state.revoke = false;
                        json!({"authenticationToken":"test-only-not-a-secret"})
                    } else {
                        json!({"errorID":50, "message":"Denied"})
                    }
                }
                "AuthenticationRequest" => {
                    authenticated = !state.revoke
                        && request["data"]["authenticationToken"] == "test-only-not-a-secret";
                    json!({"authenticated":authenticated, "reason":"Test authorization"})
                }
                _ => {
                    assert!(authenticated, "Action attempted before authentication");
                    match kind {
                        "AvailableModelsRequest" => {
                            json!({"availableModels":[{"modelID":"model-a","modelName":"Model A"},{"modelID":"model-b","modelName":"Model B"}]})
                        }
                        "HotkeysInCurrentModelRequest" => {
                            assert_eq!(request["data"]["modelID"], "model-a");
                            json!({"modelName":"Model A","availableHotkeys":[{"hotkeyID":"hotkey-a","name":"Wave"}]})
                        }
                        "CurrentModelRequest" => {
                            json!({"modelLoaded":!state.model.is_empty(),"modelID":state.model})
                        }
                        "ModelLoadRequest" => {
                            let model = request["data"]["modelID"].as_str().unwrap();
                            assert!(
                                !model.is_empty(),
                                "Empty settings must not unload the model"
                            );
                            state.model = model.to_owned();
                            state.effects.push(format!("model:{model}"));
                            json!({"modelID":model})
                        }
                        "HotkeyTriggerRequest" => {
                            assert_eq!(request["data"]["hotkeyID"], "hotkey-a");
                            state.effects.push("hotkey:hotkey-a".to_owned());
                            json!({"hotkeyID":"hotkey-a"})
                        }
                        _ => panic!("Unexpected VTS request {kind}"),
                    }
                }
            };
            let response_type = if data.get("errorID").is_some() {
                "APIError".to_owned()
            } else {
                kind.replace("Request", "Response")
            };
            (
                response_type,
                data,
                kind == "HotkeyTriggerRequest" && state.drop_trigger_reply,
            )
        };
        if disconnect {
            let _ = socket.close(None).await;
            break;
        }
        // Unrelated events must never satisfy an outstanding request.
        send(&mut socket, json!({"apiName":"VTubeStudioPublicAPI","apiVersion":"1.0","messageType":"ModelLoadedEvent","requestID":"unrelated","data":{}})).await;
        send(&mut socket, json!({"apiName":"VTubeStudioPublicAPI","apiVersion":"1.0","messageType":response_type,"requestID":request["requestID"],"data":data})).await;
    }
}

fn event(action: &str, port: u16, model: &str, command: Option<&str>) -> Value {
    let mut event = json!({
        "event":if command.is_some() { "sendToPlugin" } else { "keyDown" },
        "action":action,
        "context":{"device":"test-device","profile":"Default","key":0},
        "payload":{"settings":{"port":port,"modelID":model,"hotkeyID":"hotkey-a"}},
    });
    if let Some(command) = command {
        event["payload"]["command"] = json!(command);
        event["payload"]["requestId"] = json!(7);
    }
    event
}

async fn press(socket: &mut WebSocketStream<TcpStream>, event: Value, success: bool) {
    send(socket, event.clone()).await;
    let response = receive(socket).await;
    assert_eq!(response["context"], event["context"]);
    if success {
        assert_eq!(response["event"], "showOk");
    } else {
        assert_eq!(response["event"], "sendToPropertyInspector");
        assert_eq!(response["payload"]["ok"], false);
        assert_eq!(receive(socket).await["event"], "showAlert");
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn native_process_authorization_model_guard_and_no_replay() {
    let vts = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = vts.local_addr().unwrap().port();
    let state = Arc::new(Mutex::new(VtsState::default()));
    let server_state = state.clone();
    let server = tokio::spawn(async move {
        while let Ok((stream, _)) = vts.accept().await {
            tokio::spawn(mock_vts(stream, server_state.clone()));
        }
    });
    let deck = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let directory = std::env::temp_dir().join(format!(
        "vts-opendeck-test-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir(&directory).unwrap();
    let child = Command::new(env!("CARGO_BIN_EXE_vts-opendeck"))
        .args([
            "-port",
            &deck.local_addr().unwrap().port().to_string(),
            "-pluginUUID",
            "test-plugin",
            "-registerEvent",
            "registerPlugin",
            "-info",
            "{}",
        ])
        .env("XDG_DATA_HOME", &directory)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut runtime = Runtime { child, directory };
    let (stream, _) = tokio::time::timeout(Duration::from_secs(10), deck.accept())
        .await
        .unwrap()
        .unwrap();
    let mut socket = accept_async(stream).await.unwrap();
    assert_eq!(
        receive(&mut socket).await,
        json!({"event":"registerPlugin","uuid":"test-plugin"})
    );

    // No surprise permission popups on a keypress, and no empty-ID unloads.
    press(&mut socket, event(MODEL, port, "", None), false).await;
    press(&mut socket, event(HOTKEY, port, "model-a", None), false).await;
    assert_eq!(state.lock().await.token_requests, 0);
    send(
        &mut socket,
        event(HOTKEY, port, "model-a", Some("authorize")),
    )
    .await;
    assert_eq!(receive(&mut socket).await["payload"]["ok"], false);
    assert_eq!(state.lock().await.token_requests, 1);

    state.lock().await.allow = true;
    send(
        &mut socket,
        event(HOTKEY, port, "model-a", Some("authorize")),
    )
    .await;
    let lists = receive(&mut socket).await;
    assert_eq!(lists["payload"]["ok"], true);
    assert_eq!(lists["payload"]["models"][1]["modelID"], "model-b");
    assert_eq!(lists["payload"]["hotkeys"][0]["hotkeyID"], "hotkey-a");
    assert!(!lists.to_string().contains("test-only-not-a-secret"));
    use std::os::unix::fs::PermissionsExt;
    let token = runtime
        .directory
        .join("vts-opendeck")
        .join(format!("{port}.token"));
    assert_eq!(
        std::fs::metadata(&token).unwrap().permissions().mode() & 0o777,
        0o600
    );

    press(&mut socket, event(HOTKEY, port, "model-a", None), false).await;
    press(&mut socket, event(MODEL, port, "model-a", None), true).await;
    press(&mut socket, event(HOTKEY, port, "model-a", None), true).await;
    press(&mut socket, event(MODEL, port, "model-b", None), true).await;
    press(&mut socket, event(HOTKEY, port, "model-a", None), false).await;
    assert_eq!(
        state.lock().await.effects,
        ["model:model-a", "hotkey:hotkey-a", "model:model-b"]
    );

    // Cached auth rejection does not silently request fresh permission.
    state.lock().await.revoke = true;
    press(&mut socket, event(MODEL, port, "model-a", None), false).await;
    assert_eq!(state.lock().await.token_requests, 2);
    send(
        &mut socket,
        event(MODEL, port, "model-a", Some("authorize")),
    )
    .await;
    assert_eq!(receive(&mut socket).await["payload"]["ok"], true);
    assert_eq!(state.lock().await.token_requests, 3);

    // A lost response is ambiguous: never replay a hotkey (often a toggle).
    state.lock().await.drop_trigger_reply = true;
    press(&mut socket, event(HOTKEY, port, "", None), false).await;
    assert_eq!(
        state
            .lock()
            .await
            .effects
            .iter()
            .filter(|v| v.starts_with("hotkey:"))
            .count(),
        2
    );
    state.lock().await.drop_trigger_reply = false;
    press(&mut socket, event(MODEL, port, "model-a", None), true).await;
    assert_eq!(state.lock().await.token_requests, 3);
    socket.close(None).await.unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        while runtime.child.try_wait().unwrap().is_none() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("Plugin did not exit when OpenDeck disconnected");
    server.abort();
}
