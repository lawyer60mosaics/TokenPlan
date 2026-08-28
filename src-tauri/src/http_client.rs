use std::{sync::OnceLock, time::Duration};

pub fn get() -> reqwest::Client {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT
        .get_or_init(|| {
            reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(10))
                .timeout(Duration::from_secs(15))
                // Do not forward account keys or team headers across redirects.
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("HTTP client initialization failed")
        })
        .clone()
}
