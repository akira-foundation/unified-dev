use crate::providers::enums::ProviderOrgKind;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderOrg {
    pub id: String,
    pub login: String,
    pub kind: ProviderOrgKind,
    pub app_installed: Option<bool>,
    pub app_install_url: Option<String>,
    pub app_manage_url: Option<String>,
}
