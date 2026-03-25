pub mod cache;
pub mod detector;
pub mod discovery;
pub mod registry;
pub mod types;

pub use registry::{build_model_registry, get_or_build_registry, ModelRegistry};
pub use types::{AiModel, AiProviderGroup, AiProviderKind};
