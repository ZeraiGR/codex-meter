# Security

Report vulnerabilities using GitHub's private vulnerability reporting for this
repository. Please do not publish signing keys, access tokens or private user data
in an issue. Describe a reproducible case with synthetic data.

Update archives and the feed are signed with Ed25519; the public key is embedded
in the app. Archives are verified before extraction. A compromised signing key can
allow malicious updates, so release environment access must remain limited to trusted
maintainers. See [the release guide](docs/updates.md) for key storage and recovery.

The app stores task metadata, local journal paths and payments on the user's Mac.
It does not add application-level encryption. Current releases have no Apple notarization.
Only the latest stable version receives fixes; update from supported releases promptly.
