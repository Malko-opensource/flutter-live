#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use std::{
    ffi::{c_char, c_void, CStr, CString},
    sync::OnceLock,
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Emitter, Manager, WebviewUrl, WebviewWindowBuilder,
};
static APP: OnceLock<tauri::AppHandle> = OnceLock::new();
extern "C" {
    fn fl_audio_init(callback: extern "C" fn(*const c_char));
    fn fl_audio_command(json: *const c_char);
    fn fl_overlay_show(window: *mut c_void);
    fn fl_overlay_hide();
    fn fl_overlay_resize(height: f64);
    fn fl_overlay_drag();
    fn fl_overlay_destroy();
}
extern "C" fn audio_event(raw: *const c_char) {
    if raw.is_null() {
        return;
    }
    let text = unsafe { CStr::from_ptr(raw) }.to_string_lossy();
    if let (Some(app), Ok(value)) = (APP.get(), serde_json::from_str::<serde_json::Value>(&text)) {
        let _ = app.emit_to("main", "audio", value);
    }
}
#[tauri::command]
fn audio_command(command: serde_json::Value) -> Result<(), String> {
    let json = CString::new(command.to_string()).map_err(|_| "잘못된 오디오 요청")?;
    unsafe { fl_audio_command(json.as_ptr()) };
    Ok(())
}
#[tauri::command]
fn show_main(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}
// Order the overlay without activating the app or leaving a fullscreen Space.
fn show_overlay_window(window: &tauri::WebviewWindow) -> Result<(), String> {
    let raw = window.ns_window().map_err(|e| e.to_string())? as usize;
    window
        .run_on_main_thread(move || unsafe { fl_overlay_show(raw as *mut c_void) })
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn show_overlay(app: tauri::AppHandle, visible: bool) -> Result<(), String> {
    if !visible {
        return app
            .run_on_main_thread(|| unsafe { fl_overlay_hide() })
            .map_err(|e| e.to_string());
    }
    if let Some(w) = app.get_webview_window("overlay") {
        show_overlay_window(&w)?;
    } else {
        let w = WebviewWindowBuilder::new(
            &app,
            "overlay",
            WebviewUrl::App("index.html?overlay=1".into()),
        )
        .title("Flutter Live 자막")
        .visible(false)
        .focused(false)
        .accept_first_mouse(true)
        .background_throttling(tauri::utils::config::BackgroundThrottlingPolicy::Disabled)
        .inner_size(900.0, 160.0)
        .min_inner_size(540.0, 160.0)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible_on_all_workspaces(true)
        .build()
        .map_err(|e| e.to_string())?;
        show_overlay_window(&w)?;
    }
    Ok(())
}
#[tauri::command]
fn resize_overlay(app: tauri::AppHandle, height: f64) -> Result<(), String> {
    if !height.is_finite() {
        return Err("잘못된 자막 크기".into());
    }
    app.run_on_main_thread(move || unsafe { fl_overlay_resize(height) })
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn drag_overlay(app: tauri::AppHandle) -> Result<(), String> {
    app.run_on_main_thread(|| unsafe { fl_overlay_drag() })
        .map_err(|e| e.to_string())
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            audio_command,
            show_main,
            show_overlay,
            resize_overlay,
            drag_overlay
        ])
        .setup(|app| {
            let _ = APP.set(app.handle().clone());
            unsafe { fl_audio_init(audio_event) };
            let show = MenuItem::with_id(app, "show", "Flutter Live 열기", true, None::<&str>)?;
            let stop = MenuItem::with_id(app, "stop", "통역 중지", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &stop, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .tooltip("Flutter Live")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_main(app.clone()),
                    "stop" => {
                        let _ = app.emit_to("main", "stop", ());
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "overlay" {
                match event {
                    tauri::WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        unsafe { fl_overlay_hide() };
                    }
                    tauri::WindowEvent::Destroyed => unsafe { fl_overlay_destroy() },
                    _ => {}
                }
                return;
            }
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("Tauri application failed");
}
