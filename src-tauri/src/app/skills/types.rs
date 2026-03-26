use serde::Serialize;

#[derive(Debug, Serialize, Clone)]
pub struct InstalledSkill {
    pub id: String,
    pub name: String,
    pub description: String,
    pub enabled: bool,
    pub icon_path: Option<String>,
    pub installed_at: String,
    pub source_path: String,
}
