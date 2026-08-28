mod coding_plan;
mod deepseek;
mod http_client;
mod profiles;
mod subscription;

use profiles::Profile;
use std::{fs, path::PathBuf};
use windows_sys::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPT_INTEGER_BLOB,
};
use winreg::{enums::HKEY_CURRENT_USER, RegKey};

fn config_path() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("VolcengineTokenPlan")
        .join("profiles.dat")
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn LocalFree(hmem: isize) -> isize;
}

fn protect(input: &[u8], unprotect: bool) -> Result<Vec<u8>, String> {
    unsafe {
        let mut source = CRYPT_INTEGER_BLOB {
            cbData: input.len() as u32,
            pbData: input.as_ptr() as *mut u8,
        };
        let mut out = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: std::ptr::null_mut(),
        };
        let ok = if unprotect {
            CryptUnprotectData(
                &mut source,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                &mut out,
            )
        } else {
            CryptProtectData(
                &mut source,
                std::ptr::null(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                &mut out,
            )
        };
        if ok == 0 {
            return Err("Windows credential protection failed / Windows 凭据保护失败".into());
        }
        let result = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
        LocalFree(out.pbData as isize);
        Ok(result)
    }
}

fn load_profiles_impl() -> Result<Vec<Profile>, String> {
    let path = config_path();
    if !path.exists() {
        return Ok(vec![]);
    }
    let raw = protect(&fs::read(path).map_err(|e| e.to_string())?, true)?;
    let mut profiles: Vec<Profile> = serde_json::from_slice(&raw)
        .map_err(|_| "Invalid profile file / 配置文件无法解析；原文件已保留")?;
    // Stable IDs for pre-migration profiles, without writing on startup.
    for (i, profile) in profiles.iter_mut().enumerate() {
        if profile.id.is_empty() {
            profile.id = format!("legacy-{}", i + 1);
        }
    }
    Ok(profiles)
}

fn save_profiles_impl(profiles: Vec<Profile>) -> Result<(), String> {
    let mut ids = std::collections::HashSet::new();
    for p in &profiles {
        if p.id.is_empty()
            || !ids.insert(&p.id)
            || p.name.trim().is_empty()
            || !profiles::PROVIDERS.contains(&p.provider.as_str())
        {
            return Err("Invalid or duplicate profile / 无效或重复的配置".into());
        }
    }
    let path = config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let raw = serde_json::to_vec(&profiles).map_err(|e| e.to_string())?;
    let encrypted = protect(&raw, false)?;
    if path.exists() {
        fs::copy(&path, path.with_extension("dat.bak")).map_err(|e| e.to_string())?;
    }
    let temp = path.with_extension("dat.tmp");
    fs::write(&temp, encrypted).map_err(|e| e.to_string())?;
    fs::rename(temp, path).map_err(|e| e.to_string())
}

#[derive(serde::Serialize)]
#[serde(untagged)]
enum ProfileUsage {
    Quota(subscription::SubscriptionQuota),
    Balance(deepseek::BalanceUsage),
}

async fn query_profile_impl(profile: Profile) -> Result<ProfileUsage, String> {
    profile.validate_query()?;
    if profile.provider == "deepseek" {
        return deepseek::query(profile.api_key.trim())
            .await
            .map(ProfileUsage::Balance)
            .map_err(|error| profile.redact(&error));
    }
    let base = profile.endpoint_base()?;
    let result = coding_plan::get_coding_plan_quota(
        &base,
        profile.api_key.trim(),
        Some(profile.access_key.trim()),
        Some(profile.secret_key.trim()),
        Some(&profile.provider),
        Some(profile.organization_id.trim()),
        Some(profile.project_id.trim()),
    )
    .await;
    match result {
        Ok(mut quota) => {
            quota.tiers.retain(|tier| tier.utilization.is_finite());
            if quota.success && quota.tiers.is_empty() {
                quota.success = false;
                quota.error = Some(
                    "No recognizable active quota windows / 未找到可识别的有效套餐周期".into(),
                );
            }
            if let Some(error) = quota.error.as_mut() {
                *error = profile.redact(error);
            }
            if let Some(message) = quota.credential_message.as_mut() {
                *message = profile.redact(message);
            }
            Ok(ProfileUsage::Quota(quota))
        }
        Err(error) => Err(profile.redact(&error)),
    }
}

fn autostart_impl(enabled: bool) -> Result<(), String> {
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
        .create_subkey("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
        .map_err(|e| e.to_string())?;
    if enabled {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        key.set_value("VolcengineTokenPlan", &format!("\"{}\"", exe.display()))
            .map_err(|e| e.to_string())
    } else {
        match key.delete_value("VolcengineTokenPlan") {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}
fn autostart_state() -> bool {
    RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
        .ok()
        .and_then(|k| k.get_value::<String, _>("VolcengineTokenPlan").ok())
        .is_some()
}

mod commands {
    use super::*;
    #[tauri::command]
    pub fn load_profiles() -> Result<Vec<Profile>, String> {
        load_profiles_impl()
    }
    #[tauri::command]
    pub fn save_profiles(profiles: Vec<Profile>) -> Result<(), String> {
        save_profiles_impl(profiles)
    }
    #[tauri::command]
    pub async fn query_profile(profile: Profile) -> Result<ProfileUsage, String> {
        query_profile_impl(profile).await
    }
    #[tauri::command]
    pub fn set_autostart(enabled: bool) -> Result<(), String> {
        autostart_impl(enabled)
    }
    #[tauri::command]
    pub fn get_autostart() -> bool {
        autostart_state()
    }
    #[tauri::command]
    pub fn exit_app(app: tauri::AppHandle) {
        app.exit(0)
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri::{
        menu::{Menu, MenuItem},
        tray::TrayIconBuilder,
        Emitter, Manager,
    };
    tauri::Builder::default()
        .setup(|app| {
            let show = MenuItem::with_id(app, "show", "显示窗口 / Show", true, None::<&str>)?;
            let refresh =
                MenuItem::with_id(app, "refresh", "刷新套餐 / Refresh", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "退出 / Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &refresh, &quit])?;
            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Token Plan Monitor");
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.on_menu_event(|app, event| match event.id.as_ref() {
                "show" => {
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.show();
                        let _ = w.set_focus();
                    }
                }
                "refresh" => {
                    let _ = app.emit("refresh-requested", ());
                }
                "quit" => app.exit(0),
                _ => {}
            })
            .build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_profiles,
            commands::save_profiles,
            commands::query_profile,
            commands::set_autostart,
            commands::get_autostart,
            commands::exit_app
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dpapi_roundtrip_for_multi_provider_secrets() {
        let raw = br#"[{"provider":"kimi","api_key":"fictional-key"},{"provider":"volcengine","access_key":"fictional-ak","secret_key":"fictional-sk"}]"#;
        let encrypted = protect(raw, false).unwrap();
        assert!(!encrypted.windows(13).any(|w| w == b"fictional-key"));
        assert_eq!(protect(&encrypted, true).unwrap(), raw);
    }
}
