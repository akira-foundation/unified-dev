use axum::response::IntoResponse;
use axum::Json;

pub async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "ok": true }))
}
