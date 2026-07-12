# OCI Deployment

## Target

- APEX version: `26.1.1`
- Workspace: `APEXFROMTHEFIELD`
- Application ID: `104`
- Application alias: `AI-PROCUREMENT-AGENTS`
- Runtime URL: `https://gd7949c88ccafbd-apexfromthefield.adb.sa-saopaulo-1.oraclecloudapps.com/ords/r/apexfromthefield/ai-procurement-agents/home`
- Parsing schema: `AIPA`
- Generative AI Service: `OPEN AI` (`OPENAI`), OpenAI `gpt-5.4`

## Installed State

- The `AIPA` schema is associated with `APEXFROMTHEFIELD`.
- All 13 application tables, five package specifications, five package bodies, two triggers, indexes, and the request-number sequence are valid.
- Seed requests `PR-1001`, `PR-1002`, and `PR-1003` are loaded.
- The APEXLang application passed the live APEX 26.1 compiler and was imported as application `104`.
- The deterministic mock workflow passed review, audit, submit, approve, reject, request-changes, and invalid-transition verification.
- The `OPENAI` service credential and `gpt-5.4` endpoint passed a direct `APEX_AI.GENERATE` connectivity test.

## Builder Completion

Complete the following in APEX Builder before testing the interactive Agent:

1. Open application `104`, then Shared Components.
2. Set `OPEN AI` as the application default Generative AI Service, or select it explicitly in `Procurement Assistant Agent`.
3. Create the Agent tools exactly as defined in `apex-ai-agents-setup.md`.
4. Confirm the static ID `procurement_assistant_agent` and text response format.
5. Run the application and test the prompts from `blog-support-notes.md`.

No credential value or API key belongs in the application settings or repository.
