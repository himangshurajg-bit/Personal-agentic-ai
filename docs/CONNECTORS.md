# Connector status and setup

This table describes the standalone Android app, not Wabi's own connected accounts. A service is not connected just because the same person connected it to Wabi. There are no embedded API keys, refresh tokens, or background sync jobs. Local tasks remain on-device and are separate from remote Google Tasks.

## Status

| Service | Status | What is needed before a real integration |
|---|---|---|
| Google Tasks | Implemented in the app, not live-configured | Owner-created Google Cloud project; enable Google Tasks API; configure OAuth consent/testing and an Android OAuth client for this app's exact application ID and signing-certificate SHA-1; provide the matching Web OAuth client ID at build time as `GOOGLE_SERVER_CLIENT_ID`. User must explicitly sign in, choose the account, and grant the requested scope. Public release may require Google verification for sensitive scopes. |
| Google Calendar | Implemented in the app, not live-configured | Enable Google Calendar API in the owner-created Cloud project; configure OAuth consent/testing and use the same app-owned Android/Web OAuth clients described below; user must separately connect and grant `calendar.events.readonly`. Public release may require verification for the sensitive scope. |
| Gmail | Implemented: read-only recent Inbox view, not live-configured | Enable Gmail API in the app-owned Cloud project, configure consent and Android/Web OAuth clients, and request `gmail.readonly` only after the user taps Connect. Google classifies it as a restricted scope: public distribution requires restricted-scope OAuth verification. Google requires a security assessment when restricted data is accessed from or transmitted through a server; this implementation keeps it on-device and does not send message content to a server or AI. |
| Google Contacts | Implemented in the app, not live-configured | Enable People API in the app-owned Cloud project; configure consent/test users and Android/Web OAuth clients; add the separate `contacts.readonly` scope. Public distribution may require Google verification for this sensitive user-data scope and a privacy policy. |
| Google Drive | Implemented: app-created text files only | Enable Drive API in the app-owned Cloud project; configure the shared app-owned Android/Web OAuth clients and separately consent to `drive.file`. This version lists only app-tagged files it created and reads a file only after the user selects its row. Google Picker for selecting arbitrary existing Drive files is not integrated; do not request broad whole-Drive access as a substitute. |
| Google Docs | Implemented: app-created text Docs only | Enable Docs API and Drive API in the app-owned Cloud project. Docs uses the same limited `drive.file` grant as this app's Drive connector; it does not request a broader Docs or Drive scope. Only app-tagged Docs are listed; Google Picker for arbitrary existing files is not implemented. |
| Google Sheets | Implemented: app-created spreadsheets with bounded ranges | Enable Sheets and Drive APIs in the app-owned Cloud project; request only `drive.file`. Creates and lists app-tagged spreadsheets; Google Picker for existing files is not implemented. The scope applies to the selected spreadsheet file, not individual tabs. |
| GitHub | Not implemented | GitHub OAuth App or GitHub App registration, least-privilege repository permissions, redirect/package setup and user-selected repositories. No token is supplied. |
| Notion | Not implemented | Notion integration registration (OAuth for user sign-in or a user-created internal integration), narrow page access, and explicit page sharing. No token is supplied. |
| Slack | Not implemented | Slack app registration/OAuth redirect, minimum scopes, workspace installation/admin approval where required, and explicit channel/message actions. No token is supplied. |
| Spotify | Not implemented | Spotify developer app, OAuth redirect/client configuration and selected playback/library scopes; playback control depends on eligible Spotify account/device capabilities. No credentials are supplied. |
| Telegram | Not implemented | Decide between a bot integration (BotFather token; bot cannot silently act as a personal account) and a user-client integration (different API registration and much broader privacy/security obligations). No token or API ID supplied. |
| WhatsApp | Not implemented | Official WhatsApp Business Platform / Cloud API integration only: Meta developer/business app, approved business number, business verification/templates as applicable, webhook endpoint and secure server-side token handling. This is not a personal WhatsApp account connector. No credentials supplied. |

No inert “Connect” buttons are shown for unsupported providers. Each integration must be built and tested before it is offered in the app.

## Google Calendar implementation

The `On your phone` screen has a separate Google Calendar panel. Connect is user-started account selection and requests only `https://www.googleapis.com/auth/calendar.events.readonly`, a distinct consent grant from Google Tasks. The panel then shows the selected account and does not read events until the user taps **Load upcoming events**. That button requests at most 20 expanded upcoming events from the primary calendar only, ordered by start time. The app does not enumerate calendars, sync in the background, cache event responses, create or change events, or share Wabi's own connected Google session. Calendar API calls are GET-only. Event titles, times, and locations are visible in the app after that explicit read.

Access tokens and the connected-account label are held under Calendar-specific keys in `flutter_secure_storage` on the device. The app rejects tokens after 55 minutes, clears local Calendar credentials on expiry or API 401, and never retries an uncertain request. Calendar disconnect clears its stored token and that authorization token from the sign-in plugin cache without disconnecting the Google Tasks account. This does not erase Google's account-level consent; the owner can also revoke the app from their Google Account security settings. The app does not store a refresh token. OAuth setup is not supplied; without the Web client ID the Connect action reports “not configured” and does not mark an account connected.

### Google Calendar setup

1. In the app operator's Google Cloud project, enable the Google Calendar API as well as (if used) Google Tasks API.
2. Configure the same app-owned OAuth consent screen/test-user list and Android OAuth client used for Google Tasks. The user must separately approve Calendar's read-only scope; Tasks consent does not grant Calendar access.
3. Configure the matching Web OAuth client ID at Flutter build time as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`, as described below. No client secret belongs in the APK.
4. Before public release, confirm current Google verification requirements for `calendar.events.readonly` and complete any required verification. Test account selection, the separate scope prompt, cancellation, token expiry, disconnect, API errors and event parsing on a real Android device.

The repository does not include a Cloud project/client ID, user consent, live Calendar account, live API test, or Play/Google OAuth verification. The app is implemented but cannot connect until the owner/operator supplies the Cloud setup and build-time public Web client ID.

## Google Contacts implementation

The `On your phone` screen has a separate Google Contacts panel. Connecting is a user-started Google account selection and requests only `https://www.googleapis.com/auth/contacts.readonly`; consent is separate from Tasks and Calendar. Nothing is fetched until the person taps **Load contacts**. The request reads only the saved-contact connection list and the `names`, `emailAddresses`, and `phoneNumbers` fields, over at most three pages of 100 contacts each (up to 300 per tap). A text field searches that fetched set on the phone. The app does not request Android `READ_CONTACTS`, search the phone address book, fetch photos/birthdays/other fields, background-sync, upload, add contacts to memory, or persist contact records in the app. Data is held only in screen memory until disconnect, screen disposal, or an access error.

The connector stores only its short-lived access token plus an account label and save time in `flutter_secure_storage`; it does not store refresh tokens. The token expires locally after 55 minutes. Disconnect, local expiry, or a Google 401 clears only this connector's token/account metadata and its Google Sign-In token. Requests are GET-only and are never retried after an uncertain outcome. The account-level Google consent remains until the owner revokes it in Google Account settings.

### Google Contacts setup

1. In the app operator's Google Cloud project, enable the Google People API.
2. Add `https://www.googleapis.com/auth/contacts.readonly` to the OAuth consent screen's Data Access/scopes. Google treats OAuth access to sensitive user data as subject to applicable verification requirements. For testing, configure test users; for broader release, complete the required branding, privacy-policy/domain, scope-justification, and Google verification steps. Workspace administrators may independently restrict access.
3. Use the app-owned Android OAuth client for application ID `dev.personalagent.personal_assistant` and the relevant signing SHA-1, and the Web OAuth client ID supplied at Flutter build time as `GOOGLE_SERVER_CLIENT_ID`. Google Contacts asks separately for the scope when the owner taps Connect; Tasks/Calendar approval does not grant it. No client secret belongs in the app.
4. The app operator must publish an accurate privacy policy describing how Google contact data is requested, displayed, stored, and not shared, consistent with Google API Services User Data Policy. A real Google account connection/device API test remains to be done after setup.

The repository has no supplied Cloud project/OAuth client setup or live account. The connector is implemented, but cannot connect until the app operator configures those items and the user explicitly consents.

## Google Drive implementation

The `On your phone` screen provides a deliberately narrow Google Drive connection. The user separately consents to only `https://www.googleapis.com/auth/drive.file`; no `drive.readonly` or broad `drive` scope is requested. The app makes no network request on connect. After connecting, the owner can explicitly create a bounded plain-text file (up to 200 KB) in Drive, explicitly load the app-created-file list, then tap one row to read that one file. The list query filters on a private Drive `appProperties` marker written by this app; it does not browse or search arbitrary files. Files are not ingested into AI, local memory, or background jobs. The app does not update or delete remote files in this increment.

This first version does not include Google's Drive Picker, so it cannot select or open arbitrary pre-existing Drive files. Google's Picker requires the app operator's Cloud project/API configuration and a user-mediated picker integration; the app avoids replacing that picker with broad Drive access. The app-created file list and explicit row selection are the supported subset until a configured Picker is implemented.

Drive access tokens and account label are stored under Drive-specific keys in `flutter_secure_storage`; access tokens expire locally after 55 minutes, there is no refresh-token storage or background sync, and disconnect clears only this connector's credentials. A 401 clears local authorization and does not retry. Network errors during creation are treated as uncertain: check Drive before trying the create action again. File text is sent only to the user's Google Drive as a result of the explicit create action, and is fetched only after a row is tapped. Google account consent remains until separately revoked in Google Account settings.

### Google Drive setup

1. Enable the Google Drive API in the app operator's Google Cloud project.
2. Configure the app-owned OAuth consent screen, test users, and the app's Android client (application ID `dev.personalagent.personal_assistant` plus the relevant signing SHA-1) and Web client ID. At Flutter build time supply the public Web client ID as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; never put a client secret in the APK.
3. Have the user choose **Connect Google Drive · app files** and grant the separate `drive.file` scope. Tasks, Calendar, Contacts, and Wabi's own Google connections do not provide or imply this consent.
4. Before a public release, verify current Google consent/verification and privacy policy requirements. A live Google account/API test is still needed after Cloud setup.

There is no app-owned Cloud project/OAuth configuration in this source change; the UI will not mark Drive connected until its own account authorization succeeds. To support picking arbitrary existing Drive files later, configure Google Picker for this project and add an explicit owner-driven selection flow while retaining the narrow scope.

## Google Docs implementation

The `On your phone` screen includes a Google Docs panel. Google Docs officially accepts the `https://www.googleapis.com/auth/drive.file` OAuth scope for document creation, reading, and edits; Google lists this as a recommended non-sensitive scope. The scope is limited to files created or opened with this app (or deliberately shared with it), not the whole Drive. Docs and Drive use the same Google grant and access token when `drive.file` is authorized, so this panel requests no second Docs-specific scope. It keeps a separate local token copy so disconnecting the Docs panel does not clear the Drive connector's copy.

The user types a title and text, then explicitly taps **Create Google Doc**. This creates a native Google Doc from the submitted plain text and adds an app-private marker. **Load app-created Docs** lists only tagged native Docs; selecting a row explicitly fetches that document's text. Editing is in the visible text field and reaches Google only after **Save edits to selected Doc**. The title of an existing document is displayed read-only. The app does not scan arbitrary Drive content, import files created elsewhere, sync in the background, upload content to its AI, or ingest Docs into memory. Access is limited to the documents this app creates; arbitrary existing-file selection would need a user-mediated Google Picker implementation, not a broader scope.

The access token and account label use Docs-specific Android secure-storage keys and expire locally after 55 minutes; no refresh token is stored. Disconnect clears this connector's local copy and selected-file cache, but does not revoke Google's shared account-level `drive.file` grant or disconnect Drive. The owner can revoke that grant in Google Account security settings. A 401 clears the Docs-local credentials; network errors on edits/creation are not retried, and the screen advises checking Drive before retrying.

### Google Docs setup

1. In the app operator's Google Cloud project, enable both Google Docs API and Google Drive API.
2. Configure the app-owned OAuth consent screen/test-user list and Android OAuth client for application ID `dev.personalagent.personal_assistant` plus the relevant signing SHA-1. Use the same configured Web OAuth client ID as the other Google connectors and supply it at Flutter build time as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; never put a client secret in the APK.
3. The user chooses **Connect Google Docs · app-created docs** and grants `drive.file`. This is the same limited grant used by the app's Drive panel, not a new Docs permission. No account is connected until that setup and interactive sign-in succeed.
4. Test account selection, creation, selected-file reads, text edits, cancellation, expiry, disconnect, and API errors on a real Android account/device. Confirm applicable Google consent/privacy-policy requirements before release.

No app-owned Cloud project/OAuth client, live Google account connection, or live Docs API call is included in this repository change.



## Gmail read-only implementation

The `On your phone` screen offers Gmail as an optional read-only connector. The user must tap Connect, complete Google sign-in and separately grant only `https://www.googleapis.com/auth/gmail.readonly`. This is the narrowest general-purpose Gmail API scope that supports reading message bodies; `gmail.metadata` exposes headers/metadata but not bodies, and Gmail add-on current-message scopes do not fit this standalone Android app. The Gmail API is enabled separately in the app operator's Google Cloud project.

Google classifies `gmail.readonly` as a restricted OAuth scope. Development/testing may qualify for Google's verification exception; a public consumer release needs restricted-scope verification and accurately completed OAuth branding/privacy disclosures. Google says a security assessment is required when restricted-scope data is stored or transmitted on, or accessed through, a server. This implementation makes direct device-to-Google API calls: it has no mail backend, does not transmit message data to AI, and does not store email content. If any future version routes this data through a server, reassess CASA/security-assessment requirements before release. Workspace administrators may also block an unapproved OAuth client.

The OAuth permission itself is broad enough for Gmail message and settings reads; the screen narrows its behavior: **Load recent Inbox** fetches up to ten Inbox message IDs and only From/Subject/Date headers, and the user must tap a row before that one message body is fetched. It does not enumerate the mailbox, fetch attachment data, send or modify mail, run background scans, log bodies, write message content to disk, or ingest it into AI/memory. The selected body is held only in screen memory and is discarded when the screen is closed/disconnected. Responses above 2 MB are rejected before display. Only GET calls are implemented and a failed/uncertain read is not retried automatically.

The access token, selected account email and token time use Gmail-specific Android secure-storage keys; the bearer token expires locally after 55 minutes and is cleared on disconnect, expiry or HTTP 401. Disconnect clears the local Gmail token and transient selected-message IDs; it does not revoke Google account-level consent or disconnect the other Google service panels. The owner can revoke the app in Google Account security settings.

### Gmail setup and release limits

1. In the app operator's Google Cloud project, enable the Gmail API. Configure OAuth consent and add the account as a test user while the project is in testing.
2. Configure the app-owned Android OAuth client for application ID `dev.personalagent.personal_assistant` and the relevant signing SHA-1, plus the Web client ID passed as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Never put a client secret in the APK. No Wabi-connected Google account or credential is reused.
3. In Google OAuth Data Access, declare only `gmail.readonly` for this feature. Review the current restricted-scope verification, Google Workspace User Data / Limited Use requirements, branding, verified domains and privacy-policy requirements before offering the app publicly. A security assessment is required if restricted Gmail data is accessed from or transmitted through a server; this build deliberately has no such path.
4. A live account connection and live API request have not been tested. Google Picker is not applicable to Gmail; no scanning occurs until a user taps the explicit Inbox-load control.

## Google Tasks implementation

The `On your phone` screen contains a separate Google Tasks panel. The user starts Google sign-in from that screen. The supplied account email `himangshuraj@gmail.com` is only a selection hint shown before sign-in; it is not proof of connection or consent. Read-only access requests `https://www.googleapis.com/auth/tasks.readonly`. Editing is a separate user action requesting `https://www.googleapis.com/auth/tasks`; without that authorization, create/complete calls are rejected locally. Loading lists/tasks and creating or changing a remote task are user-triggered operations. Remote data never merges into the local task list.

The app keeps the short-lived access token only in `flutter_secure_storage` on the device, uses it only for Google Tasks API calls, removes it on disconnect/401/expiry, and does not automatically retry an uncertain request. It does not store a refresh token. The current token is treated as expired after 55 minutes; the user reconnects explicitly. OAuth setup is currently absent, so the UI reports “not configured” rather than pretending to connect.

### Required one-time Google setup

1. Create/use a Google Cloud project owned by the app operator and enable Google Tasks, Calendar, Contacts (People API), Drive, Docs, and Sheets APIs as applicable.
2. Configure the OAuth consent screen and add test users while the app is in testing. Calendar uses a separate `calendar.events.readonly` consent request; Tasks consent does not cover it. For production, complete any Google verification required for the chosen sensitive scopes.
3. Register an Android OAuth client for application ID `dev.personalagent.personal_assistant`. This workspace's debug keystore SHA-1 is `88:36:E8:1E:D4:F9:F4:4C:F0:59:EE:9A:1D:81:5D:6E:FE:33:14:D1`; register the release-signing SHA-1 separately for any release build.
4. Register/configure the Web OAuth client ID required by the Android Google Sign-In plugin. Supply that public client ID to Flutter using `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; it is an OAuth client identifier, not a private API key. Do not place a client secret in the APK.
5. Build and test interactive account selection, Tasks, Calendar, and Contacts scopes plus the shared Drive/Docs/Sheets `drive.file` grant, cancellation, token expiry, revoke/disconnect, explicit reads, and supported writes on a real Android device. Keep the user-selected account visible.

No project/client IDs, package/SHA configuration, user consent, live network test, or Google account connection are supplied by this repository change. Google Tasks, Calendar, Contacts, limited Drive app-files, and app-created Google Docs are implemented in the app but remain unavailable until that setup is completed.

## Device access and app launch

App launching is an independent reviewed device action. It uses the Android launcher-app catalog and asks the owner to approve a selected app before launch. The implementation must not add `QUERY_ALL_PACKAGES`, broad storage access, an AccessibilityService, or autonomous UI control. Accessibility services require an explicit Android Settings opt-in and are not a route to autonomous AI task planning/execution under current Google Play policy. Add only narrowly scoped Android permissions when a specific feature and its user-facing control justify them.


## Google Sheets implementation

The `On your phone` screen has a Google Sheets panel using the recommended non-sensitive `https://www.googleapis.com/auth/drive.file` scope. Google’s Sheets API accepts this scope for spreadsheet creation and cell updates; it grants file-level access to files used with this app rather than all spreadsheets. Google explicitly notes that Sheets scopes cannot be limited to a single tab, so this version lists only spreadsheets created and app-tagged by this app. It does not use Google Picker to access arbitrary existing sheets.

Connect makes no API request. After explicit user actions, the app can create a blank spreadsheet, load up to 25 app-tagged spreadsheet names, open one selected spreadsheet to read its tab metadata, then read or write one exact A1 rectangle. Ranges are limited to rows 1–50, columns A–J and 500 cells; tab-separated write input must match the selected rectangle exactly and uses `RAW` so leading `=` text is not executed as a formula. The access scope is still for the entire selected spreadsheet file (not only the chosen cells); the UI states this before connection. No spreadsheet contents are sent to AI/memory, stored locally, or synchronized in the background. Failed/uncertain writes are not retried; check the selected range before trying again.

Sheets and Drive use the same Google `drive.file` permission, but Sheets keeps its token copy under service-specific secure-storage keys and disconnecting Sheets does not clear Drive's copy. Tokens are held in Android secure storage, expire locally after 55 minutes, and are cleared after expiry or HTTP 401. No refresh token is stored.

### Google Sheets setup

1. Enable both Google Sheets API and Google Drive API in the app operator's Google Cloud project.
2. Configure the shared app-owned Google OAuth consent screen, test users, Android OAuth client for `dev.personalagent.personal_assistant` and its signing SHA-1, and Web OAuth client ID. Build with `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; never put a client secret in the APK.
3. The user taps **Connect Google Sheets · app-created files** to grant `drive.file`, then separately chooses each create, list, open, read or write action. No account is connected until the operator's OAuth setup and user sign-in succeed.
4. Confirm Google’s current OAuth verification requirements before public release. `drive.file` is listed as a recommended non-sensitive scope; basic app verification may still apply.

No app-owned Cloud project or client ID, account consent, live account, or live API request is supplied. Google Picker for opening an existing user-selected spreadsheet remains unimplemented. Keep the file scope; do not request all-spreadsheet or whole-Drive scopes as a workaround.
