mod config;
mod core;
mod db;
mod error;
mod providers;
mod security;
mod state;

use std::sync::Arc;

use config::commands::{
    attach_repo_to_organization, create_organization, delete_organization, fetch_organization_repositories,
    list_organization_repos, list_organizations, list_selected_repositories, save_selected_repositories,
};
use config::service::OrganizationService;
use config::sqlite_repository::{SqliteOrganizationRepoRepository, SqliteOrganizationRepository};
use providers::default_registry;
use security::{KeyStore, TokenCipher};
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

                let organizations = Arc::new(SqliteOrganizationRepository::new(pool.clone()));
                let repos = Arc::new(SqliteOrganizationRepoRepository::new(pool.clone()));
                let service = Arc::new(OrganizationService::new(organizations, repos, cipher));

                let registry = Arc::new(default_registry()?);

                app.manage(AppState::new(service, registry));
                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)
        })
        .invoke_handler(tauri::generate_handler![
            list_organizations,
            create_organization,
            delete_organization,
            attach_repo_to_organization,
            list_organization_repos,
            fetch_organization_repositories,
            save_selected_repositories,
            list_selected_repositories
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
