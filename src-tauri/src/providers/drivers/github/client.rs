use std::sync::Arc;

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::app::support::error::{AppError, AppResult};

pub const GITHUB_API: &str = "https://api.github.com";

pub type AuthFailureHook = Arc<dyn Fn() + Send + Sync>;

pub struct GitHubDriver {
    pub client: reqwest::Client,
    pub token: String,
    pub user_token: Option<String>,
    pub on_auth_failure: Option<AuthFailureHook>,
}

impl GitHubDriver {
    pub fn new(token: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, token, user_token: None, on_auth_failure: None })
    }

    pub fn with_user_token(mut self, user_token: Option<String>) -> Self {
        self.user_token = user_token.filter(|t| !t.is_empty());
        self
    }

    pub fn with_auth_failure_hook(mut self, hook: AuthFailureHook) -> Self {
        self.on_auth_failure = Some(hook);
        self
    }

    pub(crate) fn write_token(&self) -> &str {
        self.user_token.as_deref().unwrap_or(&self.token)
    }

    pub(crate) fn api_error(&self, status: reqwest::StatusCode, body: String) -> AppError {
        if status == reqwest::StatusCode::UNAUTHORIZED {
            if let Some(hook) = &self.on_auth_failure {
                hook();
            }
        }
        AppError::Provider(format!("GitHub API error: {status} {body}"))
    }

    pub async fn get_json<T: DeserializeOwned>(&self, url: String) -> AppResult<T> {
        let response = self
            .client
            .get(url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(self.api_error(status, body));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn get_redirect_url(&self, url: String) -> AppResult<String> {
        let no_redirect = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .redirect(reqwest::redirect::Policy::none())
            .build()?;

        let response = no_redirect
            .get(&url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        let status = response.status();
        if status.is_redirection() {
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .ok_or_else(|| AppError::Provider("Missing Location header in redirect".to_string()))?
                .to_string();
            return Ok(location);
        }

        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(self.api_error(status, body));
        }

        Ok(response.text().await?)
    }

    pub async fn post_json<B: Serialize + Send + Sync, T: DeserializeOwned>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<T> {
        let response = self
            .client
            .post(url)
            .bearer_auth(self.write_token())
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(self.api_error(status, body));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn delete(&self, url: String) -> AppResult<()> {
        let response = self
            .client
            .delete(url)
            .bearer_auth(self.write_token())
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(self.api_error(status, body));
        }

        Ok(())
    }

    pub async fn patch_json<B: Serialize + Send + Sync, T: DeserializeOwned>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<T> {
        let response = self
            .client
            .patch(url)
            .bearer_auth(self.write_token())
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(self.api_error(status, body));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn fetch_paginated<T: DeserializeOwned>(
        &self,
        url: String,
    ) -> AppResult<Vec<T>> {
        let mut page = 1;
        let mut results = Vec::new();

        loop {
            let separator = if url.contains('?') { '&' } else { '?' };
            let paged_url = format!("{url}{separator}per_page=100&page={page}");
            let chunk: Vec<T> = self.get_json(paged_url).await?;
            if chunk.is_empty() {
                break;
            }
            results.extend(chunk);
            page += 1;
        }

        Ok(results)
    }
}
