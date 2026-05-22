use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::app::support::error::{AppError, AppResult};

use super::client::GitHubDriver;

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
    pub async fn graphql<T: DeserializeOwned>(&self, query: &str, variables: serde_json::Value) -> AppResult<T> {
        #[derive(Serialize)]
        struct GraphQlRequest<'a> {
            query: &'a str,
            variables: serde_json::Value,
        }
        #[derive(Deserialize)]
        struct GraphQlResponse<T> {
            data: Option<T>,
            errors: Option<Vec<serde_json::Value>>,
        }

        let response = self
            .client
            .post("https://api.github.com/graphql")
            .bearer_auth(&self.token)
            .json(&GraphQlRequest { query, variables })
            .send()
            .await?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();

        if !status.is_success() {
            return Err(AppError::Provider(format!("GitHub GraphQL error: {status} {body}")));
        }

        let result: GraphQlResponse<T> = serde_json::from_str(&body)
            .map_err(|e| AppError::Provider(format!("GitHub GraphQL decode failed: {e} — body: {body}")))?;

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
        #[derive(Serialize)]
        struct GraphQlRequest<'a> {
            query: &'a str,
            variables: serde_json::Value,
        }
        #[derive(Deserialize)]
        struct GraphQlResponse<D> {
            data: Option<D>,
            errors: Option<Vec<serde_json::Value>>,
        }

        let mut all_items: Vec<T> = Vec::new();
        let mut cursor: Option<String> = None;

        loop {
            let mut vars = variables.clone();
            if let Some(c) = &cursor {
                vars["after"] = serde_json::Value::String(c.clone());
            } else {
                vars["after"] = serde_json::Value::Null;
            }

            let response = self
                .client
                .post("https://api.github.com/graphql")
                .bearer_auth(&self.token)
                .json(&GraphQlRequest { query, variables: vars })
                .send()
                .await?;

            let status = response.status();
            let body = response.text().await.unwrap_or_default();

            if !status.is_success() {
                return Err(AppError::Provider(format!("GitHub GraphQL error: {status} {body}")));
            }

            let result: GraphQlResponse<R> = serde_json::from_str(&body)
                .map_err(|e| AppError::Provider(format!("GitHub GraphQL decode failed: {e} — body: {body}")))?;

            if let Some(errors) = result.errors {
                let fatal: Vec<_> = errors.iter().filter(|e| {
                    e.get("type").and_then(|t| t.as_str()) != Some("FORBIDDEN")
                }).collect();
                if !fatal.is_empty() {
                    return Err(AppError::Provider(format_graphql_errors(&errors)));
                }
            }

            let data = match result.data {
                Some(d) => d,
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
