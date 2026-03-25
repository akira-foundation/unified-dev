use serde::de::DeserializeOwned;

use crate::error::{AppError, AppResult};

pub const GITLAB_API: &str = "https://gitlab.com/api/v4";

pub struct GitLabDriver {
    pub client: reqwest::Client,
    pub token: String,
}

impl GitLabDriver {
    pub fn new(token: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, token })
    }

    pub async fn get_json<T: DeserializeOwned>(&self, url: &str) -> AppResult<T> {
        let response = self
            .client
            .get(url)
            .header("Authorization", format!("Bearer {}", self.token))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("GitLab API error: {status} {body}")));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn get_response(&self, url: &str) -> AppResult<reqwest::Response> {
        let response = self
            .client
            .get(url)
            .header("Authorization", format!("Bearer {}", self.token))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("GitLab API error: {status} {body}")));
        }

        Ok(response)
    }

    pub async fn fetch_paginated<T: DeserializeOwned>(&self, base_url: &str) -> AppResult<Vec<T>> {
        let mut results = Vec::new();
        let separator = if base_url.contains('?') { '&' } else { '?' };
        let first_url = format!("{base_url}{separator}per_page=100&page=1");
        let mut next_url: Option<String> = Some(first_url);

        while let Some(url) = next_url {
            let response = self.get_response(&url).await?;
            let next_page = response
                .headers()
                .get("x-next-page")
                .and_then(|v| v.to_str().ok())
                .filter(|s| !s.is_empty())
                .map(|page| {
                    let sep = if base_url.contains('?') { '&' } else { '?' };
                    format!("{base_url}{sep}per_page=100&page={page}")
                });

            let chunk: Vec<T> = response.json().await?;
            results.extend(chunk);
            next_url = next_page;
        }

        Ok(results)
    }
}
