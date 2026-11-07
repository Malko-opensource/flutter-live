use std::{env, path::PathBuf, process::Command};
fn main() {
    if env::var("CARGO_CFG_TARGET_OS").unwrap() == "macos" {
        let out = PathBuf::from(env::var("OUT_DIR").unwrap());
        let sdk = Command::new("xcrun")
            .args(["--sdk", "macosx", "--show-sdk-path"])
            .output()
            .unwrap();
        let sdk = String::from_utf8(sdk.stdout).unwrap();
        let arch = if env::var("CARGO_CFG_TARGET_ARCH").unwrap() == "aarch64" {
            "arm64"
        } else {
            "x86_64"
        };
        let status = Command::new("xcrun")
            .args([
                "swiftc",
                "-swift-version",
                "5",
                "-parse-as-library",
                "-emit-library",
                "-static",
                "-module-name",
                "LiveAudio",
                "-target",
                &format!("{}-apple-macosx13.0", arch),
                "-sdk",
                sdk.trim(),
                "native/AudioHost.swift",
                "native/PlaybackBudget.swift",
                "native/OverlayWindow.swift",
                "-o",
            ])
            .arg(out.join("libLiveAudio.a"))
            .status()
            .unwrap();
        assert!(status.success(), "Swift audio module did not compile");
        println!("cargo:rustc-link-search=native={}", out.display());
        println!("cargo:rustc-link-lib=static=LiveAudio");
        println!("cargo:rustc-link-search=native=/usr/lib/swift");
        for f in [
            "Foundation",
            "AppKit",
            "AVFoundation",
            "AVFAudio",
            "CoreAudio",
            "AudioToolbox",
            "ScreenCaptureKit",
            "CoreMedia",
        ] {
            println!("cargo:rustc-link-lib=framework={}", f);
        }
        println!("cargo:rustc-link-lib=dylib=swiftCore");
        println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
        println!("cargo:rerun-if-changed=native/AudioHost.swift");
        println!("cargo:rerun-if-changed=native/PlaybackBudget.swift");
        println!("cargo:rerun-if-changed=native/OverlayWindow.swift");
    }
    tauri_build::build();
}
