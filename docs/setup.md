# Setup

1. Create or select an Oracle APEX 26.1 workspace.
2. Create or assign parsing schema `AIPA`.
3. Run `database/00_create_aipa_schema.sql` only if the schema does not exist and you are connected as an administrative user.
4. Connect as `AIPA` and run `database/install.sql`.
5. Check or import the APEXLang app from `application/ai-procurement-agents`.
6. Configure native APEX AI Agent tools using `docs/apex-ai-agents-setup.md`.

The default public demo mode is mock mode. Live OpenAI credentials are optional and must be configured as APEX credentials, not stored in this repository.
