fn main() {
    println!("cargo:rerun-if-changed=src/media_identity.cpp");

    cc::Build::new()
        .cpp(true)
        .file("src/media_identity.cpp")
        .flag_if_supported("-std=c++17")
        .flag_if_supported("/std:c++17")
        .flag_if_supported("/utf-8")
        .compile("media_identity_cpp");
}
