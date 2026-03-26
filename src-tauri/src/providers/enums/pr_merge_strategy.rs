#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PrMergeStrategy {
    Merge,
    Squash,
    Rebase,
}
