mod app;
mod ai;
mod commands;
mod database;
mod providers;
mod state;

use std::sync::Arc;

use commands::agent::{get_available_models, get_messages, send_message};
use commands::workspace::{check_pr_url, create_draft_pr, discard_file_changes, get_workspace_changes, list_files, read_file, run_workspace_command, search_files};
use commands::issue::{sync_issues, list_issues, get_issue, create_issue, update_issue, close_issue, delete_issue};
use commands::organization::{
    create_organization, delete_organization, get_job_logs, get_pr_checks, get_pr_comments, get_pr_files,
    list_all_selected_repositories, list_organizations, list_organizations_by_provider,
    list_selected_repositories, list_repo_pull_requests, list_repo_branches, create_repo_branch,
    delete_repo_branch, sync_pull_requests, merge_pr, post_pr_comment,
    save_selected_repositories, submit_pr_review, sync_repository_stats, sync_single_repo_stats,
    update_organization,
};
use commands::provider::{
    connect_github, create_provider, delete_provider, list_provider_organizations, list_provider_repositories,
    list_providers, test_provider_connection, update_provider_auth,
};
use commands::terminal::{
    terminal_spawn, terminal_write, terminal_resize, terminal_kill,
};
use commands::repository::{add_local_repository, add_remote_repository, delete_local_repository};
use commands::thread::{create_thread, delete_thread, list_repositories, set_thread_pr_url};
use commands::prompt::{get_prompts, save_prompt, reset_prompt};
use commands::skill::{list_installed_skills, sync_skills, get_skills, set_skill_enabled, set_skill_icon, install_skill, uninstall_skill};
use database::queries::organization_repos::SqliteOrganizationRepoRepository;
use database::queries::providers::SqliteProviderRepository;
use providers::default_registry;
use app::support::error::AppResult;
use app::support::security::{KeyStore, TokenCipher};
use state::AppState;
use app::terminal::state::TerminalState;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let setup_result: AppResult<()> = tauri::async_runtime::block_on(async {
                let pool = database::init_pool(app.handle()).await?;
                let key = KeyStore::load_or_create_key(app.handle())?;
                let cipher = Arc::new(TokenCipher::new(key));

                let providers = Arc::new(SqliteProviderRepository::new(pool.clone()));
                let organization_repos = Arc::new(SqliteOrganizationRepoRepository::new(pool.clone()));

                let provider_factory = Arc::new(default_registry()?);

                app.manage(AppState::new(
                    providers,
                    organization_repos,
                    provider_factory,
                    cipher,
                    pool.clone(),
                ));

                let terminal_manager = Arc::new(std::sync::Mutex::new(TerminalState::new()));
                app.manage(terminal_manager);

                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)
        })
        .invoke_handler(tauri::generate_handler![
            get_available_models,
            connect_github,
            create_provider,
            list_providers,
            update_provider_auth,
            delete_provider,
            test_provider_connection,
            list_provider_organizations,
            list_provider_repositories,
            create_organization,
            update_organization,
            list_organizations,
            list_organizations_by_provider,
            delete_organization,
            save_selected_repositories,
            list_selected_repositories,
            list_all_selected_repositories,
            list_repo_pull_requests,
            sync_repository_stats,
            sync_single_repo_stats,
            get_pr_comments,
            post_pr_comment,
            submit_pr_review,
            merge_pr,
            get_pr_files,
            get_pr_checks,
            get_job_logs,
            list_repo_branches,
            create_repo_branch,
            delete_repo_branch,
            sync_pull_requests,
            terminal_spawn,
            terminal_write,
            terminal_resize,
            terminal_kill,
            add_local_repository,
            add_remote_repository,
            delete_local_repository,
            list_repositories,
            create_thread,
            delete_thread,
            set_thread_pr_url,
            list_files,
            search_files,
            read_file,
            get_messages,
            send_message,
            run_workspace_command,
            get_workspace_changes,
            create_draft_pr,
            discard_file_changes,
            check_pr_url,
            get_prompts,
            save_prompt,
            reset_prompt,
            list_installed_skills,
            sync_skills,
            get_skills,
            set_skill_enabled,
            set_skill_icon,
            install_skill,
            uninstall_skill,
            sync_issues,
            list_issues,
            get_issue,
            create_issue,
            update_issue,
            close_issue,
            delete_issue,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
