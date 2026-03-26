#[derive(Debug, Clone)]
pub struct VcsBranch {
    pub name: String,
    pub sha: String,
    pub is_default: bool,
    pub is_protected: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BranchDto {
    pub name: String,
    pub sha: String,
    pub is_default: bool,
    pub is_protected: bool,
}

impl From<VcsBranch> for BranchDto {
    fn from(b: VcsBranch) -> Self {
        Self {
            name: b.name,
            sha: b.sha,
            is_default: b.is_default,
            is_protected: b.is_protected,
        }
    }
}
