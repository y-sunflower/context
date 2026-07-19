use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension};

use crate::{Conversation, CoreError, Message, SearchableMessage};

impl From<rusqlite::Error> for CoreError {
    fn from(e: rusqlite::Error) -> Self {
        CoreError::Database { msg: e.to_string() }
    }
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

pub struct Db {
    conn: Mutex<Connection>,
}

impl Db {
    pub fn open(path: &str) -> Result<Self, CoreError> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                model TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY,
                conversation_id INTEGER NOT NULL
                    REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_conversation
                ON messages(conversation_id);",
        )?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    pub fn list_conversations(&self) -> Result<Vec<Conversation>, CoreError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, title, model, created_at, updated_at
             FROM conversations ORDER BY updated_at DESC, id DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(Conversation {
                id: row.get(0)?,
                title: row.get(1)?,
                model: row.get(2)?,
                created_at: row.get(3)?,
                updated_at: row.get(4)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn create_conversation(&self, model: &str) -> Result<Conversation, CoreError> {
        let conn = self.conn.lock().unwrap();
        let ts = now();
        conn.execute(
            "INSERT INTO conversations (title, model, created_at, updated_at)
             VALUES ('New Chat', ?1, ?2, ?2)",
            rusqlite::params![model, ts],
        )?;
        Ok(Conversation {
            id: conn.last_insert_rowid(),
            title: "New Chat".to_string(),
            model: model.to_string(),
            created_at: ts,
            updated_at: ts,
        })
    }

    pub fn replace_message_and_truncate(
        &self,
        conversation_id: i64,
        message_id: i64,
        content: &str,
    ) -> Result<(), CoreError> {
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        let updated = tx.execute(
            "UPDATE messages
             SET content = ?1, created_at = ?2
             WHERE id = ?3 AND conversation_id = ?4 AND role = 'user'",
            rusqlite::params![content, now(), message_id, conversation_id],
        )?;
        if updated == 0 {
            return Err(rusqlite::Error::QueryReturnedNoRows.into());
        }
        tx.execute(
            "DELETE FROM messages WHERE conversation_id = ?1 AND id > ?2",
            rusqlite::params![conversation_id, message_id],
        )?;
        tx.execute(
            "UPDATE conversations SET updated_at = ?1 WHERE id = ?2",
            rusqlite::params![now(), conversation_id],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub fn delete_conversation(&self, id: i64) -> Result<(), CoreError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM conversations WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn rename_conversation(&self, id: i64, title: &str) -> Result<(), CoreError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE conversations SET title = ?1 WHERE id = ?2",
            rusqlite::params![title, id],
        )?;
        Ok(())
    }

    pub fn set_conversation_model(&self, id: i64, model: &str) -> Result<(), CoreError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE conversations SET model = ?1 WHERE id = ?2",
            rusqlite::params![model, id],
        )?;
        Ok(())
    }

    pub fn get_messages(&self, conversation_id: i64) -> Result<Vec<Message>, CoreError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, role, content, created_at
             FROM messages WHERE conversation_id = ?1 ORDER BY id ASC",
        )?;
        let rows = stmt.query_map([conversation_id], |row| {
            Ok(Message {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                role: row.get(2)?,
                content: row.get(3)?,
                created_at: row.get(4)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn list_searchable_messages(&self) -> Result<Vec<SearchableMessage>, CoreError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT m.id, m.conversation_id, c.title, c.updated_at,
                    m.role, m.content, m.created_at
             FROM messages m
             JOIN conversations c ON c.id = m.conversation_id
             ORDER BY c.updated_at DESC, c.id DESC, m.created_at DESC, m.id DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(SearchableMessage {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                conversation_title: row.get(2)?,
                conversation_updated_at: row.get(3)?,
                role: row.get(4)?,
                content: row.get(5)?,
                created_at: row.get(6)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn insert_message(
        &self,
        conversation_id: i64,
        role: &str,
        content: &str,
    ) -> Result<Message, CoreError> {
        let conn = self.conn.lock().unwrap();
        let ts = now();
        conn.execute(
            "INSERT INTO messages (conversation_id, role, content, created_at)
             VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![conversation_id, role, content, ts],
        )?;
        let id = conn.last_insert_rowid();
        conn.execute(
            "UPDATE conversations SET updated_at = ?1 WHERE id = ?2",
            rusqlite::params![ts, conversation_id],
        )?;
        Ok(Message {
            id,
            conversation_id,
            role: role.to_string(),
            content: content.to_string(),
            created_at: ts,
        })
    }

    /// If the conversation still has the placeholder title, derive one from
    /// the first user message.
    pub fn maybe_autotitle(&self, conversation_id: i64, content: &str) -> Result<(), CoreError> {
        let conn = self.conn.lock().unwrap();
        let title: Option<String> = conn
            .query_row(
                "SELECT title FROM conversations WHERE id = ?1",
                [conversation_id],
                |row| row.get(0),
            )
            .optional()?;
        if title.as_deref() == Some("New Chat") {
            let mut derived: String = content.split_whitespace().collect::<Vec<_>>().join(" ");
            if derived.chars().count() > 60 {
                derived = derived.chars().take(60).collect::<String>() + "…";
            }
            if !derived.is_empty() {
                conn.execute(
                    "UPDATE conversations SET title = ?1 WHERE id = ?2",
                    rusqlite::params![derived, conversation_id],
                )?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Db {
        Db::open(":memory:").unwrap()
    }

    #[test]
    fn create_and_list_conversations() {
        let db = db();
        let a = db.create_conversation("gemma4:26b").unwrap();
        assert_eq!(a.title, "New Chat");
        assert_eq!(a.model, "gemma4:26b");
        let all = db.list_conversations().unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].id, a.id);
    }

    #[test]
    fn messages_roundtrip_and_cascade_delete() {
        let db = db();
        let c = db.create_conversation("m").unwrap();
        db.insert_message(c.id, "user", "hello").unwrap();
        db.insert_message(c.id, "assistant", "hi there").unwrap();
        let msgs = db.get_messages(c.id).unwrap();
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0].role, "user");
        assert_eq!(msgs[1].content, "hi there");

        db.delete_conversation(c.id).unwrap();
        assert!(db.list_conversations().unwrap().is_empty());
        assert!(db.get_messages(c.id).unwrap().is_empty());
    }

    #[test]
    fn searchable_messages_include_conversation_metadata_and_follow_deletion() {
        let db = db();
        let kept = db.create_conversation("m").unwrap();
        db.rename_conversation(kept.id, "Kept Chat").unwrap();
        let kept_message = db.insert_message(kept.id, "user", "find me").unwrap();
        let deleted = db.create_conversation("m").unwrap();
        db.insert_message(deleted.id, "assistant", "remove me")
            .unwrap();
        db.delete_conversation(deleted.id).unwrap();

        let messages = db.list_searchable_messages().unwrap();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].id, kept_message.id);
        assert_eq!(messages[0].conversation_id, kept.id);
        assert_eq!(messages[0].conversation_title, "Kept Chat");
        assert_eq!(messages[0].role, "user");
        assert_eq!(messages[0].content, "find me");
        assert!(messages[0].conversation_updated_at >= kept.updated_at);
    }

    #[test]
    fn autotitle_from_first_message() {
        let db = db();
        let c = db.create_conversation("m").unwrap();
        db.maybe_autotitle(c.id, "explain lifetimes in rust")
            .unwrap();
        let all = db.list_conversations().unwrap();
        assert_eq!(all[0].title, "explain lifetimes in rust");

        // A second call must not overwrite the derived title.
        db.maybe_autotitle(c.id, "something else").unwrap();
        assert_eq!(
            db.list_conversations().unwrap()[0].title,
            "explain lifetimes in rust"
        );
    }

    #[test]
    fn autotitle_truncates_long_content() {
        let db = db();
        let c = db.create_conversation("m").unwrap();
        db.maybe_autotitle(c.id, &"word ".repeat(40)).unwrap();
        let title = db.list_conversations().unwrap()[0].title.clone();
        assert!(title.chars().count() <= 61);
        assert!(title.ends_with('…'));
    }

    #[test]
    fn rename_and_set_model() {
        let db = db();
        let c = db.create_conversation("m").unwrap();
        db.rename_conversation(c.id, "My Chat").unwrap();
        db.set_conversation_model(c.id, "llama3:latest").unwrap();
        let all = db.list_conversations().unwrap();
        assert_eq!(all[0].title, "My Chat");
        assert_eq!(all[0].model, "llama3:latest");
    }

    #[test]
    fn replacing_user_message_truncates_later_history() {
        let db = db();
        let conversation = db.create_conversation("m").unwrap();
        db.insert_message(conversation.id, "user", "first").unwrap();
        db.insert_message(conversation.id, "assistant", "first answer")
            .unwrap();
        let selected = db
            .insert_message(conversation.id, "user", "revise me")
            .unwrap();
        db.insert_message(conversation.id, "assistant", "old answer")
            .unwrap();

        db.replace_message_and_truncate(conversation.id, selected.id, "revised")
            .unwrap();

        let messages = db.get_messages(conversation.id).unwrap();
        assert_eq!(messages.len(), 3);
        assert_eq!(messages[0].content, "first");
        assert_eq!(messages[1].content, "first answer");
        assert_eq!(messages[2].content, "revised");
    }

    #[test]
    fn replacing_requires_a_user_message_from_the_conversation() {
        let db = db();
        let conversation = db.create_conversation("m").unwrap();
        let assistant = db
            .insert_message(conversation.id, "assistant", "not editable")
            .unwrap();

        assert!(db
            .replace_message_and_truncate(conversation.id, assistant.id, "still not editable")
            .is_err());
        assert_eq!(db.get_messages(conversation.id).unwrap().len(), 1);
    }
}
