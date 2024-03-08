# checkout-action

[![release](https://img.shields.io/github/release/taiki-e/checkout-action?style=flat-square&logo=github)](https://github.com/taiki-e/checkout-action/releases/latest)
[![github actions](https://img.shields.io/github/actions/workflow/status/taiki-e/checkout-action/ci.yml?branch=main&style=flat-square&logo=github)](https://github.com/taiki-e/checkout-action/actions)

GitHub Action for checking out a repository. (Simplified `actions/checkout` alternative without depending on Node.js.)

- [Usage](#usage)
- [Why not actions/checkout?](#why-not-actionscheckout)
- [Related Projects](#related-projects)
- [License](#license)

## Usage

This action currently provides a minimal subset of the features provided by `actions/checkout`.

The features supported as of v1.0.0 are purely based on my use cases within public repositories, but feel free to submit an issue if you see something missing in your use case. See [issues](https://github.com/taiki-e/checkout-action/issues) for known unsupported features.

```yaml
- uses: taiki-e/checkout-action@v1
```

Almost equivalent to (for public repositories):

```yaml
- uses: actions/checkout@v4
  with:
    persist-credentials: false
```

## Why not actions/checkout?

As of 2024-03-08, the latest version of `actions/checkout` that uses node20 [doesn't work on CentOS 7](https://github.com/actions/runner/issues/2906).

Also, in `actions/*` actions, each update of the Node.js used increments the major version (it is the correct behavior for compatibility although), so workflows that use it require maintenance on a regular basis. (Unless you have fully automated dependency updates.)

## Related Projects

- [install-action]: GitHub Action for installing development tools (mainly from GitHub Releases).
- [create-gh-release-action]: GitHub Action for creating GitHub Releases based on changelog.
- [upload-rust-binary-action]: GitHub Action for building and uploading Rust binary to GitHub Releases.
- [setup-cross-toolchain-action]: GitHub Action for setup toolchains for cross compilation and cross testing for Rust.
- [cache-cargo-install-action]: GitHub Action for `cargo install` with cache.

[cache-cargo-install-action]: https://github.com/taiki-e/cache-cargo-install-action
[create-gh-release-action]: https://github.com/taiki-e/create-gh-release-action
[install-action]: https://github.com/taiki-e/install-action
[setup-cross-toolchain-action]: https://github.com/taiki-e/setup-cross-toolchain-action
[upload-rust-binary-action]: https://github.com/taiki-e/upload-rust-binary-action

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
