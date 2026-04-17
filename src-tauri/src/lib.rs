mod app;
mod ai;
mod commands;
mod database;
mod providers;
mod state;

use std::sync::Arc;

use commands::agent::{abort_agent, get_available_models, get_messages, send_message};
use commands::workspace::{check_pr_url, create_draft_pr, discard_file_changes, get_workspace_changes, list_files, read_file, run_workspace_command, search_files};
use commands::issue::{sync_issues, list_issues, get_issue, create_issue, update_issue, close_issue, delete_issue, delegate_issue_to_agent};
use commands::organization::{
    create_organization, delete_organization, get_job_logs, get_pr_checks, get_pr_comments, get_pr_files,
    list_all_selected_repositories, list_organizations, list_organizations_by_provider,
    list_selected_repositories, list_repo_pull_requests, list_repo_branches, create_repo_branch,
    delete_repo_branch, sync_pull_requests, merge_pr, post_pr_comment,
    save_selected_repositories, submit_pr_review, sync_repository_stats, sync_single_repo_stats,
    update_organization,
};
use commands::provider::{
    connect_github, create_provider, delete_provider, get_rate_limit, install_github_app, list_provider_organizations, list_provider_repositories,
    list_providers, test_provider_connection, update_provider_auth,
    uninstall_github_app,
};
use commands::terminal::{
    terminal_spawn, terminal_write, terminal_resize, terminal_kill,
};
use commands::repository::{add_local_repository, add_remote_repository, delete_local_repository, link_local_repository_to_organization, set_local_repository_remote};
use commands::thread::{
    create_thread, create_thread_from_branch, create_thread_from_pull_request, create_thread_with_title, delete_thread,
    list_repositories, list_thread_source_branches, list_thread_source_issues,
    list_thread_source_pull_requests, rename_thread, set_thread_pr_url, update_repository_settings,
};
use commands::prompt::{get_prompts, save_prompt, reset_prompt};
use commands::settings::{get_sync_settings, get_visibility_preferences, upsert_sync_settings, upsert_visibility_preferences, reset_sync_settings, reset_visibility_preferences, get_remote_settings, set_remote_enabled, regenerate_remote_pairing_code, revoke_remote_device, touch_org_synced_at};
use commands::license::{activate_license, checkout_license, claim_license_request, claim_license_verify, clear_license, downgrade_license, get_license, list_invoices, manage_license, register_license, verify_license};
use commands::skill::{list_installed_skills, sync_skills, get_skills, set_skill_enabled, set_skill_icon, install_skill, uninstall_skill, fetch_recommended_skills, fetch_skills_from_repo};
use commands::mcp::{list_mcp_servers, add_mcp_server, remove_mcp_server, set_mcp_server_enabled, connect_mcp_server, disconnect_mcp_server, cancel_mcp_connect};
use commands::system::check_dependencies;
use commands::updater::{check_for_updates, install_update};
use commands::usage::get_usage;
use commands::profile::{get_user_profile, set_user_profile};
use providers::default_registry;
use app::support::error::AppResult;
use app::support::security::{KeyStore, TokenCipher};
use state::AppState;
use app::terminal::state::TerminalState;
use tauri::{Emitter, Listener, Manager};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let setup_result: AppResult<()> = tauri::async_runtime::block_on(async {
                let pool = database::init_pool(app.handle()).await?;
                let key = KeyStore::load_or_create_key(app.handle())?;
                let cipher = Arc::new(TokenCipher::new(key));

                let provider_factory = Arc::new(default_registry()?);

                app.manage(AppState::new(
                    provider_factory,
                    cipher,
                    pool.clone(),
                ));

                let app_state = app.state::<AppState>();
                if let Ok(remote_settings) = app::settings::remote::get(app_state).await {
                    if remote_settings.enabled {
                        let app_state = app.state::<AppState>();
                        let _ = app::remote::start(
                            &remote_settings,
                            app_state.db_pool.clone(),
                            app_state.abort_handles.clone(),
                            app.handle().clone(),
                        ).await;
                    }
                }

                let terminal_manager = Arc::new(std::sync::Mutex::new(TerminalState::new()));
                app.manage(terminal_manager);

                app::settings::poller::start(app.handle().clone());

                Ok(())
            });

            setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)?;

            let app_handle = app.handle().clone();
            app.listen("deep-link://new-url", move |event: tauri::Event| {
                if let Ok(urls) = serde_json::from_str::<Vec<String>>(event.payload()) {
                    for url in urls {
                        if let Ok(parsed) = reqwest::Url::parse(&url) {
                            if parsed.scheme() == "akira" && parsed.path() == "/license/activate" {
                                if let Some(session_id) = parsed.query_pairs().find(|(k, _)| k == "session_id").map(|(_, v): (_, std::borrow::Cow<str>)| v.into_owned()) {
                                    let _ = app_handle.emit("license://activate", session_id);
                                }
                            }
                        }
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_available_models,
            abort_agent,
            connect_github,
            install_github_app,
            uninstall_github_app,
            create_provider,
            list_providers,
            update_provider_auth,
            delete_provider,
            test_provider_connection,
            list_provider_organizations,
            list_provider_repositories,
            get_rate_limit,
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
            set_local_repository_remote,
            link_local_repository_to_organization,
            list_repositories,
            update_repository_settings,
            create_thread,
            create_thread_with_title,
            create_thread_from_branch,
            create_thread_from_pull_request,
            delete_thread,
            rename_thread,
            set_thread_pr_url,
            list_thread_source_issues,
            list_thread_source_pull_requests,
            list_thread_source_branches,
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
            fetch_recommended_skills,
            fetch_skills_from_repo,
            sync_issues,
            list_issues,
            get_issue,
            create_issue,
            update_issue,
            close_issue,
            delete_issue,
            delegate_issue_to_agent,
            get_sync_settings,
            upsert_sync_settings,
            reset_sync_settings,
            touch_org_synced_at,
            get_visibility_preferences,
            upsert_visibility_preferences,
            reset_visibility_preferences,
            get_remote_settings,
            set_remote_enabled,
            regenerate_remote_pairing_code,
            revoke_remote_device,
            activate_license,
            checkout_license,
            get_license,
            verify_license,
            clear_license,
            manage_license,
            downgrade_license,
            list_invoices,
            register_license,
            claim_license_request,
            claim_license_verify,
            list_mcp_servers,
            add_mcp_server,
            remove_mcp_server,
            set_mcp_server_enabled,
            connect_mcp_server,
            disconnect_mcp_server,
            cancel_mcp_connect,
            check_for_updates,
            install_update,
            check_dependencies,
            get_usage,
            get_user_profile,
            set_user_profile,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
