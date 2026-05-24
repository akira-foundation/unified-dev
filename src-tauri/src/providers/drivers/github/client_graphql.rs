use std::time::Duration;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::app::support::error::{AppError, AppResult};

use super::client::GitHubDriver;

const GRAPHQL_URL: &str = "https://api.github.com/graphql";
const MAX_ATTEMPTS: u32 = 3;

#[derive(Serialize)]
struct GraphQlRequest<'a> {
    query: &'a str,
    variables: serde_json::Value,
}

fn format_graphql_errors(errors: &[serde_json::Value]) -> String {
    let messages: Vec<String> = errors
        .iter()
        .map(|e| {
            let msg = e.get("message").and_then(|m| m.as_str()).unwrap_or("unknown error");
            let kind = e.get("type").and_then(|t| t.as_str()).unwrap_or("");
            match kind {
                "NOT_FOUND" => format!("{msg} Make sure your GitHub token has access to this private repository or organization."),
                "FORBIDDEN" => format!("{msg} Your GitHub token does not have permission to perform this action."),
                _ => msg.to_string(),
            }
        })
        .collect();
    messages.join("; ")
}

impl GitHubDriver {
    async fn execute_graphql(&self, query: &str, variables: &serde_json::Value) -> AppResult<String> {
        let mut last_transient = String::new();

        for attempt in 1..=MAX_ATTEMPTS {
            if attempt > 1 {
                tokio::time::sleep(Duration::from_millis(300 * u64::from(attempt - 1))).await;
            }

            let sent = self
                .client
                .post(GRAPHQL_URL)
                .bearer_auth(self.write_token())
                .json(&GraphQlRequest { query, variables: variables.clone() })
                .send()
                .await;

            let response = match sent {
                Ok(response) => response,
                Err(error) => {
                    last_transient = format!("request failed: {error}");
                    continue;
                }
            };

            let status = response.status();
            let body = match response.text().await {
                Ok(body) => body,
                Err(error) => {
                    last_transient = format!("response read failed: {error}");
                    continue;
                }
            };

            if !status.is_success() {
                return Err(AppError::Provider(format!("GitHub GraphQL error: {status} {body}")));
            }

            if body.trim().is_empty() {
                last_transient = "empty response body".to_string();
                continue;
            }

            return Ok(body);
        }

        Err(AppError::Provider(format!(
            "GitHub GraphQL request did not return a body after {MAX_ATTEMPTS} attempts: {last_transient}"
        )))
    }

    pub async fn graphql<T: DeserializeOwned>(&self, query: &str, variables: serde_json::Value) -> AppResult<T> {
        #[derive(Deserialize)]
        struct GraphQlResponse<T> {
            data: Option<T>,
            errors: Option<Vec<serde_json::Value>>,
        }

        let body = self.execute_graphql(query, &variables).await?;

        let result: GraphQlResponse<T> = serde_json::from_str(&body)
            .map_err(|e| AppError::Provider(format!("GitHub GraphQL decode failed: {e} - body: {body}")))?;

        if let Some(errors) = result.errors {
            if !errors.is_empty() {
                return Err(AppError::Provider(format_graphql_errors(&errors)));
            }
        }

        result.data.ok_or_else(|| AppError::Provider("GitHub GraphQL: no data returned".to_string()))
    }

    pub async fn graphql_paginated<T, F, R>(
        &self,
        query: &str,
        variables: serde_json::Value,
        extract: F,
    ) -> AppResult<Vec<T>>
    where
        R: DeserializeOwned,
        F: Fn(R) -> (Vec<T>, bool, Option<String>),
    {
        #[derive(Deserialize)]
        struct GraphQlResponse<D> {
            data: Option<D>,
            errors: Option<Vec<serde_json::Value>>,
        }

        let mut all_items: Vec<T> = Vec::new();
        let mut cursor: Option<String> = None;

        loop {
            let mut vars = variables.clone();
            vars["after"] = cursor
                .as_ref()
                .map(|c| serde_json::Value::String(c.clone()))
                .unwrap_or(serde_json::Value::Null);

            let body = self.execute_graphql(query, &vars).await?;

            let result: GraphQlResponse<R> = serde_json::from_str(&body)
                .map_err(|e| AppError::Provider(format!("GitHub GraphQL decode failed: {e} - body: {body}")))?;

            if let Some(errors) = result.errors {
                let fatal: Vec<_> = errors
                    .iter()
                    .filter(|e| e.get("type").and_then(|t| t.as_str()) != Some("FORBIDDEN"))
                    .collect();
                if !fatal.is_empty() {
                    return Err(AppError::Provider(format_graphql_errors(&errors)));
                }
            }

            let data = match result.data {
                Some(data) => data,
                None => break,
            };
            let (items, has_next, end_cursor) = extract(data);
            all_items.extend(items);

            if !has_next {
                break;
            }
            cursor = end_cursor;
        }

        Ok(all_items)
    }
}
