use sqlx::SqlitePool;

use super::dto::{AutopilotJobDto, AutopilotThreadDto, SaveJobRequest, UpdateJobRequest, SaveThreadRequest, UpdateThreadRequest, WriteLogRequest};
use super::types::{AutopilotJobRecord, AutopilotThreadRecord};

pub async fn save_job(pool: &SqlitePool, req: SaveJobRequest) -> Result<(), String> {
    sqlx::query(
        "INSERT INTO autopilot_jobs (id, repo_id, repo_name, config, issues, total, created, status, started_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, 'running', ?)",
    )
    .bind(&req.id)
    .bind(&req.repo_id)
    .bind(&req.repo_name)
    .bind(&req.config)
    .bind(&req.issues)
    .bind(req.total)
    .bind(&req.started_at)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn update_job(pool: &SqlitePool, req: UpdateJobRequest) -> Result<(), String> {
    sqlx::query(
        "UPDATE autopilot_jobs SET created = ?, status = ?, finished_at = ?, issues = COALESCE(?, issues), total = COALESCE(?, total) WHERE id = ?",
    )
    .bind(req.created)
    .bind(&req.status)
    .bind(&req.finished_at)
    .bind(&req.issues)
    .bind(req.total)
    .bind(&req.id)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn save_thread(pool: &SqlitePool, req: SaveThreadRequest) -> Result<(), String> {
    sqlx::query(
        "INSERT INTO autopilot_threads (id, job_id, issue_id, issue_number, issue_title, thread_id, status, sort_order)
         VALUES (?, ?, ?, ?, ?, NULL, 'pending', ?)",
    )
    .bind(&req.id)
    .bind(&req.job_id)
    .bind(&req.issue_id)
    .bind(req.issue_number)
    .bind(&req.issue_title)
    .bind(req.sort_order)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn update_thread(pool: &SqlitePool, req: UpdateThreadRequest) -> Result<(), String> {
    sqlx::query(
        "UPDATE autopilot_threads SET thread_id = ?, status = ? WHERE id = ?",
    )
    .bind(&req.thread_id)
    .bind(&req.status)
    .bind(&req.id)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn delete_job(pool: &SqlitePool, job_id: String) -> Result<(), String> {
    sqlx::query("DELETE FROM autopilot_jobs WHERE id = ?")
        .bind(&job_id)
        .execute(pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn delete_thread(pool: &SqlitePool, thread_row_id: String) -> Result<(), String> {
    sqlx::query("DELETE FROM autopilot_threads WHERE id = ?")
        .bind(&thread_row_id)
        .execute(pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn write_log(pool: &SqlitePool, req: WriteLogRequest) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO autopilot_logs (job_id, thread_row_id, event, model_id, repo_name, issue_id, issue_number, detail, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&req.job_id)
    .bind(&req.thread_row_id)
    .bind(&req.event)
    .bind(&req.model_id)
    .bind(&req.repo_name)
    .bind(&req.issue_id)
    .bind(req.issue_number)
    .bind(&req.detail)
    .bind(&now)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub async fn list_jobs(pool: &SqlitePool) -> Result<Vec<AutopilotJobDto>, String> {
    let jobs = sqlx::query_as::<_, AutopilotJobRecord>(
        "SELECT * FROM autopilot_jobs ORDER BY started_at DESC",
    )
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    let mut result = Vec::with_capacity(jobs.len());

    for job in jobs {
        let threads = sqlx::query_as::<_, AutopilotThreadRecord>(
            "SELECT * FROM autopilot_threads WHERE job_id = ? ORDER BY sort_order ASC",
        )
        .bind(&job.id)
        .fetch_all(pool)
        .await
        .map_err(|e| e.to_string())?;

        result.push(AutopilotJobDto {
            id: job.id,
            repo_id: job.repo_id,
            repo_name: job.repo_name,
            config: job.config,
            issues: job.issues,
            total: job.total,
            created: job.created,
            status: job.status,
            started_at: job.started_at,
            finished_at: job.finished_at,
            threads: threads
                .into_iter()
                .map(|t| AutopilotThreadDto {
                    id: t.id,
                    job_id: t.job_id,
                    issue_id: t.issue_id,
                    issue_number: t.issue_number,
                    issue_title: t.issue_title,
                    thread_id: t.thread_id,
                    status: t.status,
                    sort_order: t.sort_order,
                })
                .collect(),
        });
    }

    Ok(result)
}
