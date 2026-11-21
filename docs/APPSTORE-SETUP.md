# App Store Connect setup (Mike does these)

Four things, all in Mike's own browser and accounts. Claude never sees the key file or passwords. Do them in this order.

## 1. Register the bundle id

Page: <https://developer.apple.com/account/resources/identifiers/add/bundleId>

1. Choose **App IDs**, Continue, then **App**, Continue.
2. Description: `Pocket XR iOS`
3. Bundle ID: **Explicit**, `com.hayeco.pocketxr.ios`
4. Capabilities: leave all off. Continue, then Register.

If the page first asks to accept a new Apple Developer Program License Agreement, accept it: App Store Connect
refuses uploads until it is accepted.

## 2. Create the app record

Page: <https://appstoreconnect.apple.com/apps>

1. Press the blue **+** next to Apps, then **New App**.
2. Platforms: **iOS**
3. Name: `Pocket XR` (the App Store name must be unique; if it is taken, try `Pocket XR Spatial Desktop` and tell
   Claude which one you used)
4. Primary Language: **English (UK)**
5. Bundle ID: pick `Pocket XR iOS - com.hayeco.pocketxr.ios`
6. SKU: `pocketxr-ios`
7. User Access: **Full Access**. Create.

## 3. Make an API key for the builds

Page: <https://appstoreconnect.apple.com/access/integrations/api>

1. Under **Team Keys**, press **Generate API Key** (or the **+**).
2. Name: `Pocket XR iOS CI`
3. Access: **Admin**. App Manager can upload builds, but with an API key only Admin can create the distribution
   certificate that cloud-managed signing needs. The key lives only in the private repo's secrets.
4. Generate, then **Download** the `.p8` file. Apple lets you download it only once.
5. Note the **Key ID** (in the key's row) and the **Issuer ID** (above the list).

## 4. Put the key into the repo's secrets

Page: <https://github.com/pocket-xr/pocket-xr-ios/settings/secrets/actions>

Press **New repository secret** three times:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | the whole text of the `.p8` file, from `-----BEGIN PRIVATE KEY-----` to `-----END PRIVATE KEY-----` |

Then delete the downloaded `.p8` from Downloads, or keep it somewhere safe, as you prefer.

## After that

Tell Claude, which then runs the **TestFlight** workflow: it builds, signs and uploads a build. With no iPhone yet,
nobody can install it, but it proves signing and upload work and the build passes Apple's automatic checks.
