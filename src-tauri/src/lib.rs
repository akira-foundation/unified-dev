mod agents;
mod chat;
mod commands;
mod core;
mod db;
mod error;
mod providers;
mod security;
mod services;
mod state;
mod terminal;
mod repositories;
mod threads;

use std::sync::Arc;

use commands::agent_commands::{agents_get_messages, agents_send_message, create_draft_pr, get_available_models, get_workspace_changes, list_files, read_file, search_files, run_workspace_command};
use commands::organization_commands::{
    create_organization, delete_organization, list_organizations, list_organizations_by_provider,
    list_selected_repositories, save_selected_repositories,
};
use commands::provider_commands::{
    create_provider, delete_provider, list_provider_organizations, list_provider_repositories, list_providers,
    test_provider_connection, update_provider_auth,
};
use commands::terminal_commands::{
    terminal_spawn, terminal_write, terminal_resize, terminal_kill,
};
use commands::repository_commands::{add_local_repository, delete_local_repository, create_thread, delete_thread, list_repositories};
use db::organization_repo_repository::SqliteOrganizationRepoRepository;
use db::organization_repository::SqliteOrganizationRepository;
use db::provider_repository::SqliteProviderRepository;
use providers::default_registry;
use security::{KeyStore, TokenCipher};
use services::organization_repo_service::OrganizationRepoService;
use services::organization_service::OrganizationService;
use services::provider_service::ProviderService;
use state::AppState;
use terminal::manager::TerminalManager;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let setup_result: error::AppResult<()> = tauri::async_runtime::block_on(async {
                let pool = db::init_pool(app.handle()).await?;
                let key = KeyStore::load_or_create_key(app.handle())?;
                let cipher = TokenCipher::new(key);

                let providers = Arc::new(SqliteProviderRepository::new(pool.clone()));
                let organizations = Arc::new(SqliteOrganizationRepository::new(pool.clone()));
                let organization_repos = Arc::new(SqliteOrganizationRepoRepository::new(pool.clone()));

                let provider_service = Arc::new(ProviderService::new(
                    providers.clone(),
                    organizations.clone(),
                    cipher,
                ));
                let organization_service = Arc::new(OrganizationService::new(
                    organizations.clone(),
                    providers.clone(),
                ));
                let organization_repo_service = Arc::new(OrganizationRepoService::new(
                    organization_repos.clone(),
                ));

                let provider_factory = Arc::new(default_registry()?);

                app.manage(AppState::new(
                    provider_service,
                    organization_service,
                    organization_repo_service,
                    provider_factory,
                    pool.clone(),
                ));

                let terminal_manager = Arc::new(std::sync::Mutex::new(TerminalManager::new()));
                app.manage(terminal_manager);

                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)
        })
        .invoke_handler(tauri::generate_handler![
            get_available_models,
            create_provider,
            list_providers,
            update_provider_auth,
            delete_provider,
            test_provider_connection,
            list_provider_organizations,
            list_provider_repositories,
            create_organization,
            list_organizations,
            list_organizations_by_provider,
            delete_organization,
            save_selected_repositories,
            list_selected_repositories,
            terminal_spawn,
            terminal_write,
            terminal_resize,
            terminal_kill,
            add_local_repository,
            delete_local_repository,
            list_repositories,
            create_thread,
            delete_thread,
            list_files,
            search_files,
            read_file,
            agents_get_messages,
            agents_send_message,
            run_workspace_command,
            get_workspace_changes,
            create_draft_pr,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
