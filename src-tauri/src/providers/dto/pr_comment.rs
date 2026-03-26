#[derive(Debug, Clone)]
pub struct VcsPrComment {
    pub id: String,
    pub author: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PrCommentDto {
    pub id: String,
    pub author: String,
    pub body: String,
    pub created_at: String,
}

impl From<VcsPrComment> for PrCommentDto {
    fn from(c: VcsPrComment) -> Self {
        Self {
            id: c.id,
            author: c.author,
            body: c.body,
            created_at: c.created_at,
        }
    }
}
