use crate::app::billing::PRODUCT_SLUG;

pub fn checkout_url(plan_key: &str) -> String {
    let base = match env!("AKIRA_BILLING_URL") {
        "" => "http://billing.test",
        value => value,
    };
    format!("{}/subscribe/{PRODUCT_SLUG}/{plan_key}", base.trim_end_matches('/'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_subscribe_url_with_plan_key() {
        let url = checkout_url("pro_monthly");
        assert!(url.ends_with("/subscribe/unified-dev/pro_monthly"));
        assert!(!url.contains("//subscribe"));
    }
}
