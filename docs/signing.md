# Signing Tracer

macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes on every build, so macOS would ask for permission again after each rebuild. A self-signed certificate, created once, keeps the signature stable.

## One-time setup

1. Open **Keychain Access**.
2. From the menu bar, choose **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - **Name:** `Tracer Local Signing`
   - **Identity Type:** Self Signed Root
   - **Certificate Type:** Code Signing
4. Click **Create**, then **Done**. It goes into your login keychain.
5. Check it's usable:

   ```bash
   security find-identity -v -p codesigning
   ```

   You should see a line ending in `"Tracer Local Signing"`.

The first time `scripts/bundle.sh` signs with it, macOS may ask to let `codesign` use the key. Choose **Always Allow**.

## Using a different identity

Set `TRACER_SIGN_IDENTITY` to the certificate's name, for example an Apple Developer ID:

```bash
TRACER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/bundle.sh
```

Changing the identity later resets the Screen Recording permission once.
