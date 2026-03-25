use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::error::{AppError, AppResult};

pub const GITHUB_API: &str = "https://api.github.com";

pub struct GitHubDriver {
    pub client: reqwest::Client,
    pub token: String,
}

impl GitHubDriver {
    pub fn new(token: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, token })
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
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn get_text(&self, url: String) -> AppResult<String> {
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
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(response.text().await?)
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
            return Err(AppError::Provider(format!("GitHub API error: {status} {body}")));
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
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn patch_json<B: Serialize + Send + Sync, T: DeserializeOwned>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<T> {
        let response = self
            .client
            .patch(url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn put_json<B: Serialize + Send + Sync>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<()> {
        let response = self
            .client
            .put(url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(())
    }

    pub async fn graphql<T: DeserializeOwned>(&self, query: &str, variables: serde_json::Value) -> AppResult<T> {
        use serde::Deserialize;

        #[derive(serde::Serialize)]
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

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("GitHub GraphQL error: {status} {body}")));
        }

        let result: GraphQlResponse<T> = response.json().await?;

        if let Some(errors) = result.errors {
            if !errors.is_empty() {
                return Err(AppError::Provider(format!(
                    "GitHub GraphQL errors: {}",
                    serde_json::to_string(&errors).unwrap_or_default()
                )));
            }
        }

        result.data.ok_or_else(|| AppError::Provider("GitHub GraphQL: no data returned".to_string()))
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
