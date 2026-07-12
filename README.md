# AI Procurement Agents

Public Oracle APEX 26.1 demo app for a blog post about moving from insight to action with native APEX AI Agents.

The app models a small purchase request workflow. A requester creates a request, the Procurement Assistant Agent retrieves controlled application context, checks deterministic procurement policies in PL/SQL, recommends an approval route, explains risk, asks for confirmation, and then invokes approved workflow actions through APEX AI Tools.

## Architecture

- Target APEX workspace: `APEXFROMTHEFIELD`
- Parsing/application schema: `AIPA`
- Target platform: Oracle APEX 26.1 on Autonomous Database
- LLM provider setting: existing Generative AI Service `OPENAI`, OpenAI `gpt-5.4`
- Default public mode: deterministic mock mode, no secrets required
- APEX app artifacts: `application/ai-procurement-agents/`
- Database install artifacts: `database/`

## Repository Layout

- `database/00_create_aipa_schema.sql`: optional admin script to create `AIPA`
- `database/install.sql`: creates tables, packages, and seed data in the current schema
- `application/ai-procurement-agents/`: APEXLang application artifacts
- `docs/architecture.md`: system design and sequence diagram
- `docs/apex-ai-agents-setup.md`: exact native APEX AI Agent and AI Tool setup
- `docs/blog-support-notes.md`: how the demo supports the blog narrative

## Install

1. Connect as an admin user only if the `AIPA` schema does not exist, then run:

```sql
@database/00_create_aipa_schema.sql
```

2. Connect as `AIPA`, then run:

```sql
@database/install.sql
```

3. From the public repository root, check the APEXLang app for workspace `APEXFROMTHEFIELD`:

```bash
scripts/check-apexlang.sh
```

The default workflow is check-only. Do not import into a live workspace until a `db_connection_name` and explicit approval are provided.

## Mock and Live Modes

Seed data enables mock mode:

```sql
select setting_value
  from aipa_app_settings
 where setting_name = 'MOCK_MODE_ENABLED';
```

Mock mode persists agent runs, messages, tool calls, and recommendations so the demo is fully usable without OpenAI credentials.

For live mode, select the existing `OPENAI` Generative AI Service configured for OpenAI `gpt-5.4` and its APEX credential in Builder. Store only the credential static ID or reference name in settings. Never store API keys in this repository.

## Verification

Offline checks from the public repository root:

```bash
scripts/check-apexlang.sh
```

Database checks after install:

```sql
select status, count(*) from aipa_purchase_requests group by status;
select * from table(json_table(pk_aipa_policy_engine.get_findings_json(1), '$[*]' columns finding_code varchar2(60) path '$.finding_code'));
declare
    l_response clob;
begin
    l_response := pk_aipa_agent_orchestration.run_ai_review(1);
    dbms_output.put_line(dbms_lob.substr(l_response, 4000, 1));
    commit;
end;
/
```

## Safety Notes

The APEX page/application changes are represented as APEXLang and documentation only. Exported APEX page files under an `apex/` directory must not be edited directly.
