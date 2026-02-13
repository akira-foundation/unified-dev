mod config;
mod db;
mod error;
mod security;
mod state;

use std::sync::Arc;

use config::commands::{
    attach_repo_to_organization, create_organization, delete_organization, list_organization_repos,
    list_organizations,
};
use config::service::OrganizationService;
use config::sqlite_repository::{SqliteOrganizationRepoRepository, SqliteOrganizationRepository};
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

                app.manage(AppState::new(service));
                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)
        })
        .invoke_handler(tauri::generate_handler![
            list_organizations,
            create_organization,
            delete_organization,
            attach_repo_to_organization,
            list_organization_repos
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
