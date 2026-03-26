use crate::ai::agents::registry;

pub async fn get_available_models() -> Result<registry::ModelRegistry, String> {
    Ok(registry::get_or_build_registry().await)
}
