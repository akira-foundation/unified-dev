use std::sync::Arc;

use akira_billing::gate::{Gate, GateOptions, LicenseLoader, LocalConsumption};
use akira_billing::types::SignedLicense;
use chrono::Duration;
use futures_util::FutureExt;
use sqlx::SqlitePool;

use crate::app::support::error::{AppError, AppResult};

use super::persist::load_envelope;
use super::signed_license::verify_envelope;

const GATE_GRACE_WINDOW_DAYS: i64 = 365;

pub fn build(pool: SqlitePool) -> Arc<Gate> {
    Arc::new(Gate::new(GateOptions {
        loader: Some(build_loader(pool.clone())),
        local_consumption: Some(build_local_consumption(pool)),
        grace_window: Duration::days(GATE_GRACE_WINDOW_DAYS),
        now: None,
    }))
}

fn build_loader(pool: SqlitePool) -> LicenseLoader {
    Arc::new(move || {
        let pool = pool.clone();
        async move {
            let envelope = load_envelope(&pool)
                .await
                .map_err(license_loader_error)?;
            let Some(envelope) = envelope else {
                return Ok(None);
            };
            let payload = match verify_envelope(&pool, &envelope).await {
                Ok(payload) => payload,
                Err(_) => return Ok(None),
            };
            let signed = SignedLicense {
                key_id: envelope.key_id,
                algorithm: envelope.algorithm,
                payload: envelope.payload,
                signature: envelope.signature,
                valid_until: payload.valid_until.clone(),
            };
            Ok(Some((signed, payload)))
        }
        .boxed()
    })
}

fn build_local_consumption(pool: SqlitePool) -> LocalConsumption {
    Arc::new(move |feature: String| {
        let pool = pool.clone();
        async move { count_for(&pool, &feature).await.map_err(consumption_error) }.boxed()
    })
}

async fn count_for(pool: &SqlitePool, feature: &str) -> AppResult<u64> {
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    let count: i64 = match feature {
        "repos" => sqlx::query_scalar(
            "SELECT COUNT(*) FROM repos r JOIN organizations o ON o.id = r.organization_id JOIN providers p ON p.id = o.provider_id WHERE p.customer_id = ?",
        )
        .bind(&customer_id)
        .fetch_one(pool)
        .await?,
        "orgs" => sqlx::query_scalar(
            "SELECT COUNT(*) FROM organizations o JOIN providers p ON p.id = o.provider_id WHERE p.customer_id = ?",
        )
        .bind(&customer_id)
        .fetch_one(pool)
        .await?,
        "threads" => sqlx::query_scalar(
            "SELECT COUNT(*) FROM threads t JOIN local_repositories r ON r.id = t.repo_id WHERE t.status != 'closed' AND r.customer_id = ?",
        )
        .bind(&customer_id)
        .fetch_one(pool)
        .await?,
        _ => 0,
    };
    Ok(count.max(0) as u64)
}

fn license_loader_error(err: AppError) -> akira_billing::Error {
    akira_billing::Error::Api {
        status: 0,
        code: format!("license_loader: {err}"),
        body: None,
    }
}

fn consumption_error(err: AppError) -> akira_billing::Error {
    akira_billing::Error::Api {
        status: 0,
        code: format!("local_consumption: {err}"),
        body: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_license, setup_test_db};

    #[tokio::test]
    async fn count_for_repos_includes_seeded_rows() {
        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;
        sqlx::query("UPDATE license SET customer_id = 'cust-1' WHERE id = 'local'")
            .execute(&pool)
            .await
            .expect("license customer");
        sqlx::query("INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at, customer_id) VALUES ('p1', 'gh', 'github', 'pat', '{}', '2026-01-01', 'cust-1')")
            .execute(&pool)
            .await
            .expect("provider");
        sqlx::query("INSERT INTO organizations (id, name, provider_id, created_at) VALUES ('o1', 'org', 'p1', '2026-01-01')")
            .execute(&pool)
            .await
            .expect("org");
        sqlx::query("INSERT INTO repos (id, owner, repo_name, organization_id, created_at) VALUES ('r1', 'o', 'n', 'o1', '2026-01-01')")
            .execute(&pool)
            .await
            .expect("repo");
        assert_eq!(count_for(&pool, "repos").await.expect("count"), 1);
    }

    #[tokio::test]
    async fn count_for_threads_excludes_other_customers() {
        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;
        sqlx::query("UPDATE license SET customer_id = 'cust-1' WHERE id = 'local'")
            .execute(&pool)
            .await
            .expect("license customer");
        sqlx::query("INSERT INTO local_repositories (id, name, default_branch, source_path, workspace_root, created_at, customer_id) VALUES ('lr1', 'mine', 'main', '/mine', '/ws/mine', '2026-01-01', 'cust-1')")
            .execute(&pool)
            .await
            .expect("repo mine");
        sqlx::query("INSERT INTO local_repositories (id, name, default_branch, source_path, workspace_root, created_at, customer_id) VALUES ('lr2', 'theirs', 'main', '/theirs', '/ws/theirs', '2026-01-01', 'cust-2')")
            .execute(&pool)
            .await
            .expect("repo theirs");
        sqlx::query("INSERT INTO threads (id, repo_id, title, workspace_path, branch, status, created_at) VALUES ('t1', 'lr1', 'mine', '/ws/mine', 'b', 'open', '2026-01-01')")
            .execute(&pool)
            .await
            .expect("thread mine");
        sqlx::query("INSERT INTO threads (id, repo_id, title, workspace_path, branch, status, created_at) VALUES ('t2', 'lr2', 'theirs', '/ws/theirs', 'b', 'open', '2026-01-01')")
            .execute(&pool)
            .await
            .expect("thread theirs");
        assert_eq!(count_for(&pool, "threads").await.expect("count"), 1);
    }

    #[tokio::test]
    async fn count_for_unknown_feature_returns_zero() {
        let pool = setup_test_db().await;
        assert_eq!(count_for(&pool, "unknown").await.expect("count"), 0);
    }

    #[tokio::test]
    async fn gate_check_denies_when_no_license_envelope() {
        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;
        let gate = build(pool);
        let access = gate.check("repos").await.expect("check");
        assert!(!access.allowed);
        assert_eq!(access.reason, "no_license");
    }
}
