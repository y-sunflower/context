mod chat;
mod db;

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};

use ollama_rs::Ollama;

uniffi::setup_scaffolding!();

/// Global runtime for streaming work spawned from sync FFI entry points.
static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
});

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("database error: {msg}")]
    Database { msg: String },
    #[error("ollama error: {msg}")]
    Ollama { msg: String },
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct Conversation {
    pub id: i64,
    pub title: String,
    pub model: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct Message {
    pub id: i64,
    pub conversation_id: i64,
    pub role: String,
    pub content: String,
    pub created_at: i64,
}

/// A persisted message plus the conversation metadata needed by global search.
#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchableMessage {
    pub id: i64,
    pub conversation_id: i64,
    pub conversation_title: String,
    pub conversation_updated_at: i64,
    pub role: String,
    pub content: String,
    pub created_at: i64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ModelInfo {
    pub name: String,
    pub size_bytes: u64,
}

/// Implemented on the Swift side to receive streamed chat output.
#[uniffi::export(foreign)]
pub trait ChatListener: Send + Sync {
    fn on_token(&self, token: String);
    fn on_complete(&self, message: Message);
    fn on_error(&self, error: String);
}

#[derive(uniffi::Object)]
pub struct ContextCore {
    db: db::Db,
    cancels: Mutex<HashMap<i64, Arc<AtomicBool>>>,
}

#[uniffi::export]
impl ContextCore {
    #[uniffi::constructor]
    pub fn new(db_path: String) -> Result<Arc<Self>, CoreError> {
        Ok(Arc::new(Self {
            db: db::Db::open(&db_path)?,
            cancels: Mutex::new(HashMap::new()),
        }))
    }

    pub fn list_conversations(&self) -> Result<Vec<Conversation>, CoreError> {
        self.db.list_conversations()
    }

    /// Persist a new conversation and its first user message atomically.
    pub fn create_conversation_with_message(
        &self,
        model: String,
        content: String,
    ) -> Result<Conversation, CoreError> {
        self.db.create_conversation_with_message(&model, &content)
    }

    pub fn delete_conversation(&self, conversation_id: i64) -> Result<(), CoreError> {
        self.db.delete_conversation(conversation_id)
    }

    pub fn rename_conversation(
        &self,
        conversation_id: i64,
        title: String,
    ) -> Result<(), CoreError> {
        self.db.rename_conversation(conversation_id, &title)
    }

    pub fn get_messages(&self, conversation_id: i64) -> Result<Vec<Message>, CoreError> {
        self.db.get_messages(conversation_id)
    }

    pub fn list_searchable_messages(&self) -> Result<Vec<SearchableMessage>, CoreError> {
        self.db.list_searchable_messages()
    }

    /// Ask `conversation_id`'s current stream (if any) to stop. The partial
    /// response is still persisted and delivered via `on_complete`.
    pub fn cancel(&self, conversation_id: i64) {
        if let Some(flag) = self.cancels.lock().unwrap().get(&conversation_id) {
            flag.store(true, Ordering::Relaxed);
        }
    }

    /// Persist the user message, then stream the assistant reply in the
    /// background, reporting deltas through `listener`.
    pub fn send_message(
        self: Arc<Self>,
        conversation_id: i64,
        content: String,
        model: String,
        listener: Arc<dyn ChatListener>,
    ) -> Result<(), CoreError> {
        self.db.set_conversation_model(conversation_id, &model)?;
        self.db.insert_message(conversation_id, "user", &content)?;
        self.db.maybe_autotitle(conversation_id, &content)?;

        self.generate_reply(conversation_id, model, listener)
    }

    /// Stream a reply using the conversation's already-persisted history.
    pub fn generate_reply(
        self: Arc<Self>,
        conversation_id: i64,
        model: String,
        listener: Arc<dyn ChatListener>,
    ) -> Result<(), CoreError> {
        self.db.set_conversation_model(conversation_id, &model)?;
        self.spawn_reply(conversation_id, model, listener)
    }

    /// Replace an earlier user message, remove the later history, then stream
    /// a new assistant response in the same conversation.
    pub fn resend_message(
        self: Arc<Self>,
        conversation_id: i64,
        message_id: i64,
        content: String,
        model: String,
        listener: Arc<dyn ChatListener>,
    ) -> Result<(), CoreError> {
        self.db.set_conversation_model(conversation_id, &model)?;
        self.db
            .replace_message_and_truncate(conversation_id, message_id, &content)?;

        self.spawn_reply(conversation_id, model, listener)
    }
}

impl ContextCore {
    fn spawn_reply(
        self: Arc<Self>,
        conversation_id: i64,
        model: String,
        listener: Arc<dyn ChatListener>,
    ) -> Result<(), CoreError> {
        let history = self.db.get_messages(conversation_id)?;
        let cancel = Arc::new(AtomicBool::new(false));
        self.cancels
            .lock()
            .unwrap()
            .insert(conversation_id, cancel.clone());

        let this = self.clone();
        RUNTIME.spawn(async move {
            let result = chat::stream_chat(model, history, cancel, |token| {
                listener.on_token(token);
            })
            .await;
            this.cancels.lock().unwrap().remove(&conversation_id);
            match result {
                Ok(full) => match this.db.insert_message(conversation_id, "assistant", &full) {
                    Ok(message) => listener.on_complete(message),
                    Err(e) => listener.on_error(e.to_string()),
                },
                Err(e) => listener.on_error(e.to_string()),
            }
        });
        Ok(())
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ContextCore {
    /// Models available in the local Ollama instance.
    pub async fn list_models(&self) -> Result<Vec<ModelInfo>, CoreError> {
        let models = Ollama::default()
            .list_local_models()
            .await
            .map_err(|e| CoreError::Ollama { msg: e.to_string() })?;
        Ok(models
            .into_iter()
            .map(|m| ModelInfo {
                name: m.name,
                size_bytes: m.size,
            })
            .collect())
    }
}
