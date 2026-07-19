//! End-to-end smoke test against a live Ollama instance:
//! `cargo run --release --example smoke -- <db_path> <model> <prompt>`

use std::io::Write;
use std::sync::mpsc;
use std::sync::Arc;

use context_core::{ChatListener, ContextCore, Message};

struct PrintListener {
    done: mpsc::Sender<Result<Message, String>>,
}

impl ChatListener for PrintListener {
    fn on_token(&self, token: String) {
        print!("{token}");
        std::io::stdout().flush().ok();
    }
    fn on_complete(&self, message: Message) {
        self.done.send(Ok(message)).ok();
    }
    fn on_error(&self, error: String) {
        self.done.send(Err(error)).ok();
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let db_path = args
        .next()
        .expect("usage: smoke <db_path> <model> <prompt>");
    let model = args.next().expect("missing model");
    let prompt = args.next().expect("missing prompt");

    let core = ContextCore::new(db_path).expect("open db");
    let conversation = core
        .create_conversation_with_message(model.clone(), prompt)
        .expect("create");
    let (tx, rx) = mpsc::channel();

    core.clone()
        .generate_reply(conversation.id, model, Arc::new(PrintListener { done: tx }))
        .expect("send");

    match rx.recv_timeout(std::time::Duration::from_secs(300)) {
        Ok(Ok(message)) => {
            println!("\n--- complete: {} chars persisted", message.content.len());
            let history = core.get_messages(conversation.id).expect("history");
            println!(
                "--- {} messages in conversation {}",
                history.len(),
                conversation.id
            );
        }
        Ok(Err(e)) => {
            eprintln!("\n--- stream error: {e}");
            std::process::exit(1);
        }
        Err(_) => {
            eprintln!("\n--- timed out");
            std::process::exit(1);
        }
    }
}
