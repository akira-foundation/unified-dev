use serde::de::DeserializeOwned;

use crate::support::error::{AppError, AppResult};

pub const BITBUCKET_API: &str = "https://api.bitbucket.org/2.0";

#[derive(Debug, serde::Deserialize)]
pub struct BitbucketPage<T> {
    pub values: Vec<T>,
    pub next: Option<String>,
}

pub struct BitbucketDriver {
    pub client: reqwest::Client,
    pub username: String,
    pub password: String,
}

impl BitbucketDriver {
    pub fn new(username: String, password: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, username, password })
    }

    pub async fn get_json<T: DeserializeOwned>(&self, url: &str) -> AppResult<T> {
        let response = self
            .client
            .get(url)
            .basic_auth(&self.username, Some(&self.password))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("Bitbucket API error: {status} {body}")));
        }

        Ok(response.json::<T>().await?)
    }

    pub async fn fetch_paginated<T: DeserializeOwned>(&self, base_url: &str) -> AppResult<Vec<T>> {
        let mut results = Vec::new();
        let separator = if base_url.contains('?') { '&' } else { '?' };
        let first_url = format!("{base_url}{separator}pagelen=100");
        let mut next_url: Option<String> = Some(first_url);

        while let Some(url) = next_url {
            let page: BitbucketPage<T> = self.get_json(&url).await?;
            results.extend(page.values);
            next_url = page.next;
        }

        Ok(results)
    }
}
