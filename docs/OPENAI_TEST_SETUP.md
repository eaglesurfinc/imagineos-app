# Connect a personal OpenAI API account for testing

Use one project API key, entered through the ImagineOS parent connection form. No Enterprise plan is required for the connection. API billing is separate from ChatGPT; ChatGPT Plus image allowances cannot currently fund this integration through [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations). Account/model eligibility still needs verification.

## Account and key

1. Sign into [OpenAI Platform](https://platform.openai.com/) with your personal account.
2. In the project selector, create/select **ImagineOS testing** to separate experiments from other applications.
3. Open [API billing](https://platform.openai.com/settings/organization/billing/overview). Add your payment method and choose a small credit purchase if required. Review the amount yourself; this guide does not authorize a purchase or an automated generation request. Leave automatic top-ups disabled for the initial test if offered.
4. Open the test project's **Settings → Limits → Spend → Edit spend limit**. A $5 monthly test limit is a suggested starting point. Enable **Enforce a hard limit**, if available, and save. A spend alert alone does not stop requests. Enforcement can lag, so recorded spend can slightly exceed the limit. See the [official spend-limit instructions](https://developers.openai.com/api/docs/guides/spend-limits).
5. Open [API keys](https://platform.openai.com/api-keys), with the test project selected. Choose **Create new secret key**, owned by your account, and name it **ImagineOS initial test**. Use an ordinary project API key, not an Admin API key. If restricting permissions, allow model listing for connection verification and model/image requests for the eventual test. A read-only key cannot generate images. See [API setup](https://developers.openai.com/api/docs/quickstart) and [permissions](https://developers.openai.com/api/docs/guides/rbac).
6. Copy the secret into your password manager when it is displayed. Do not send it in chat, screenshots, email, Git, client configuration or Vercel build variables. If exposed, revoke it in OpenAI and create a replacement.

## Connect inside ImagineOS

1. Open [ImagineOS](https://imagineos-app.vercel.app/).
2. Choose **For parents**, sign into the parent account, and unlock parent settings.
3. Open **AI provider accounts → OpenAI → Connect API key**.
4. Paste the key into **Provider API key**.
5. Enter the **ImagineOS parent password**. This is the password for ImagineOS, not your OpenAI account password.
6. Choose **Verify and connect**. Success displays **API connection verified**.

The server verifies the key using read-only model discovery and stores it encrypted in the existing server Vault. Clients receive connection metadata only. Verification does not generate an image, establish a usable balance or prove access to a specific image model. The existing Supabase URL/publishable-key settings stay as they are; the provider secret belongs in this parent form.

If verification fails, check that the full key was copied, the selected project/key is active, model-list access is allowed and the ImagineOS password is correct. Report only the displayed error text, never the key. A revoked or restricted key can fail even when billing is configured. Provider image-model eligibility or organization verification may require additional steps shown by OpenAI.

## Before the first paid image

Connection and generation are separate gates. Keep generation disabled until the server validation, moderation/recognition, durable job accounting and reviewed client acceptance path are integrated. Obtain explicit authorization for a concrete capped benchmark, within the existing plan, before any paid request. Use only fictional adult-created drawings; do not upload the founder's private debugging photo or real child data. Do not retry an uncertain charged attempt automatically.

The proposed image-edit transport and its model/scope are recorded in `DECISIONS.md`; implementation evidence and remaining work belong only in `STATUS.md`. Connecting a key does not complete Stage 6 or make the real-child pilot available.
