# AppVault

AppVault is an offline-first macOS menu-bar utility that asks for Touch ID and/or a locally configured password when a selected app launches or is reactivated.

## Security and privacy

- Protection configuration and salted password verifiers live in the user's Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- AppVault never stores plaintext passwords, reads biometric information, or sends data to a server.
- Optional sync is intentionally not implemented or enabled. Its boundary is an AES-GCM opaque envelope: a future provider may receive only ciphertext, nonce, and a format version. The encryption key remains in the Keychain; no Supabase service-role credential belongs in this client.
- No sensitive values are logged.

## Important limitation

macOS does not let a normal user-space app make an arbitrary application unbypassably locked. A determined user can quit AppVault, launch an executable through another mechanism, or alter the system environment. AppVault provides a practical launch-monitoring deterrent, not parental controls, MDM enforcement, or disk encryption. Use FileVault and separate macOS accounts for stronger boundaries.

## Release checklist (the remaining Xcode work)

1. Create/open the Xcode app target around this package source; attach `Configuration/Info.plist` and `Configuration/AppVault.entitlements`.
2. For private use, build with the included ad-hoc (`-`) signing configuration; no Apple Developer account is required. macOS may still show a first-launch trust warning for an app copied from another machine.
3. Run the package tests and test launch monitoring, cancellation, Keychain migration, and Touch ID on physical Apple Silicon and Intel Macs.
4. If you later distribute outside your own Macs, replace ad-hoc signing with a Developer ID Application certificate, notarize with `notarytool`, staple it, then run `Scripts/create-dmg.sh`. Verify the final DMG on a clean Mac.

The script never claims to sign or notarize; it verifies the app it receives before packaging.
