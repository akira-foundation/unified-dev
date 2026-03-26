use crate::providers::enums::ProviderOrgKind;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderOrg {
    pub id: String,
    pub login: String,
    pub kind: ProviderOrgKind,
}
