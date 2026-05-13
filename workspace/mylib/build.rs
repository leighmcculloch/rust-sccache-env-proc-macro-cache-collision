use std::process::Command;

fn main() {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .expect("git rev-parse failed");
    let sha = String::from_utf8(output.stdout).unwrap().trim().to_string();

    println!("cargo:rerun-if-changed=../.git/index");
    println!("cargo:rerun-if-changed=../.git/HEAD");
    println!("cargo:rerun-if-changed=../.git/refs");

    println!("cargo:rustc-env=GIT_REVISION={}", sha);

    println!("cargo:warning=mylib/build.rs ran: GIT_REVISION={}", sha);
}
