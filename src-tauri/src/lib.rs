mod commands;
mod core;
mod db;
mod error;
mod providers;
mod security;
mod services;
mod state;

use std::sync::Arc;

use commands::organization_commands::{
    create_organization, delete_organization, list_organizations, list_organizations_by_provider,
};
use commands::provider_commands::{create_provider, delete_provider, list_providers};
use db::organization_repository::SqliteOrganizationRepository;
use db::provider_repository::SqliteProviderRepository;
use providers::default_registry;
use security::{KeyStore, TokenCipher};
use services::organization_service::OrganizationService;
use services::provider_service::ProviderService;
use state::AppState;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let setup_result: error::AppResult<()> = tauri::async_runtime::block_on(async {
                let pool = db::init_pool(app.handle()).await?;
                let key = KeyStore::load_or_create_key()?;
                let cipher = TokenCipher::new(key);

                let providers = Arc::new(SqliteProviderRepository::new(pool.clone()));
                let organizations = Arc::new(SqliteOrganizationRepository::new(pool.clone()));

                let provider_service = Arc::new(ProviderService::new(
                    providers.clone(),
                    organizations.clone(),
                    cipher,
                ));
                let organization_service = Arc::new(OrganizationService::new(
                    organizations.clone(),
                    providers.clone(),
                ));

                let provider_factory = Arc::new(default_registry()?);

                app.manage(AppState::new(
                    provider_service,
                    organization_service,
                    provider_factory,
                ));
                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)
        })
        .invoke_handler(tauri::generate_handler![
            create_provider,
            list_providers,
            delete_provider,
            create_organization,
            list_organizations,
            list_organizations_by_provider,
            delete_organization
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
