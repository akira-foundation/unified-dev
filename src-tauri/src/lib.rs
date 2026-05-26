mod app;
mod ai;
mod commands;
mod database;
mod providers;
mod setup;
mod state;
mod tracker;

#[cfg(test)]
mod test_utils;

use commands::autopilot::{
    autopilot_list_jobs, autopilot_save_job, autopilot_update_job,
    autopilot_save_thread, autopilot_update_thread, autopilot_delete_job, autopilot_delete_thread, autopilot_write_log,
};
use commands::agent::{abort_agent, get_available_models, get_messages, send_message};
use commands::workspace::{check_pr_ci, check_pr_url, create_draft_pr, discard_file_changes, get_workspace_changes, list_files, open_in_editor, read_file, run_workspace_command, search_files};
use commands::issue::{sync_issues, list_issues, get_issue, create_issue, update_issue, close_issue, delete_issue, delegate_issue_to_agent};
use commands::open_source::{
    fetch_github_contribution_summary,
    fetch_github_contributed_repositories,
    fetch_github_pull_requests,
    fetch_github_issues,
    fetch_github_reviews,
    fetch_github_contribution_calendar,
    fetch_github_year_overview,
    sync_github_open_source_contributions,
};
use commands::organization::{
    create_organization, delete_organization, get_job_logs, get_pr_checks, get_pr_comments, get_pr_files,
    list_all_selected_repositories, list_organizations, list_organizations_by_provider,
    list_selected_repositories, list_repo_pull_requests, list_repo_branches, create_repo_branch,
    delete_repo_branch, sync_pull_requests, merge_pr, post_pr_comment, delete_pr_comment,
    save_selected_repositories, submit_pr_review, sync_repository_stats, sync_single_repo_stats,
    update_organization,
};
use commands::provider::{
    connect_github, reconnect_github, create_provider, create_provider_repository, delete_provider_repository, delete_provider, get_rate_limit, install_github_app, list_provider_organizations, list_provider_repositories,
    list_providers, test_provider_connection, update_provider_auth,
    uninstall_github_app,
};
use commands::terminal::{
    terminal_spawn, terminal_write, terminal_resize, terminal_kill,
};
use commands::repository::{add_local_repository, add_remote_repository, delete_local_repository, link_local_repository_to_organization, set_local_repository_remote};
use commands::thread::{
    create_thread, create_thread_from_branch, create_thread_from_pull_request, create_thread_with_title, delete_thread,
    get_repo_provider_login, list_repositories, list_thread_source_branches, list_thread_source_issues,
    list_thread_source_pull_requests, rename_thread, set_thread_pr_url, update_repository_settings,
    get_thread_pr_review_context,
};
use commands::prompt::{get_prompts, save_prompt, reset_prompt};
use commands::settings::{get_sync_settings, get_visibility_preferences, upsert_sync_settings, upsert_visibility_preferences, reset_sync_settings, reset_visibility_preferences, get_remote_settings, set_remote_enabled, regenerate_remote_pairing_code, revoke_remote_device, touch_org_synced_at};
use commands::auth::{is_authenticated, list_oauth_providers, oauth_login, oauth_logout};
use commands::notification::{
    clear_notifications, delete_notification, get_notification_prefs, list_notifications,
    mark_all_notifications_read, mark_notification_read, set_notification_prefs,
    unread_notifications_count,
};
use commands::license::{activate_license, checkout_url, claim_license_request, claim_license_verify, clear_license, downgrade_license, get_license, get_product_plans, list_invoices, manage_license, resume_license, verify_license};
use commands::skill::{list_installed_skills, sync_skills, get_skills, set_skill_enabled, set_skill_icon, install_skill, uninstall_skill, fetch_recommended_skills, fetch_skills_from_repo};
use commands::mcp::{list_mcp_servers, add_mcp_server, remove_mcp_server, set_mcp_server_enabled, connect_mcp_server, disconnect_mcp_server, cancel_mcp_connect};
use commands::system::check_dependencies;
use commands::tracker::{
    tracker_close_issue, tracker_connect, tracker_create_issue, tracker_delete_issue,
    tracker_disconnect, tracker_get_issue, tracker_list_issues, tracker_list_projects,
    tracker_list_teams, tracker_providers, tracker_status, tracker_sync, tracker_update_issue,
};
use commands::projects::{
    project_create, project_delete, project_list, project_repo_create, project_repo_delete,
    project_repo_list, project_repo_update, project_update, repo_source_add, repo_source_list,
    repo_source_remove,
};
use commands::updater::{check_for_updates, install_update};
use commands::usage::{get_feature_usage, get_usage};
use commands::profile::{get_user_profile, set_user_profile};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .setup(setup::init)
        .invoke_handler(tauri::generate_handler![
            get_available_models,
            abort_agent,
            connect_github,
            reconnect_github,
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
            create_provider_repository,
            delete_provider_repository,
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
            delete_pr_comment,
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
            get_thread_pr_review_context,
            get_repo_provider_login,
            list_thread_source_issues,
            list_thread_source_pull_requests,
            list_thread_source_branches,
            list_files,
            search_files,
            read_file,
            open_in_editor,
            get_messages,
            send_message,
            run_workspace_command,
            get_workspace_changes,
            create_draft_pr,
            discard_file_changes,
            check_pr_url,
            check_pr_ci,
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
            tracker_connect,
            tracker_status,
            tracker_disconnect,
            tracker_providers,
            tracker_sync,
            tracker_list_issues,
            tracker_get_issue,
            tracker_create_issue,
            tracker_update_issue,
            tracker_close_issue,
            tracker_delete_issue,
            tracker_list_projects,
            tracker_list_teams,
            project_list,
            project_create,
            project_update,
            project_delete,
            project_repo_list,
            project_repo_create,
            project_repo_update,
            project_repo_delete,
            repo_source_list,
            repo_source_add,
            repo_source_remove,
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
            checkout_url,
            get_product_plans,
            get_license,
            verify_license,
            clear_license,
            manage_license,
            downgrade_license,
            resume_license,
            list_invoices,
            claim_license_request,
            claim_license_verify,
            oauth_login,
            oauth_logout,
            is_authenticated,
            list_oauth_providers,
            list_notifications,
            unread_notifications_count,
            mark_notification_read,
            mark_all_notifications_read,
            delete_notification,
            clear_notifications,
            get_notification_prefs,
            set_notification_prefs,
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
            get_feature_usage,
            get_user_profile,
            set_user_profile,
            fetch_github_contribution_summary,
            fetch_github_contributed_repositories,
            fetch_github_pull_requests,
            fetch_github_issues,
            fetch_github_reviews,
            fetch_github_contribution_calendar,
            fetch_github_year_overview,
            sync_github_open_source_contributions,
            autopilot_list_jobs,
            autopilot_save_job,
            autopilot_update_job,
            autopilot_save_thread,
            autopilot_update_thread,
            autopilot_delete_job,
            autopilot_delete_thread,
            autopilot_write_log,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
