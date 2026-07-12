# Native APEX AI Agents Setup

This document is the authoritative manual setup for native Oracle APEX 26.1 AI Agent tooling when offline APEXLang compiler truth cannot verify environment-specific built-in AI Tool plugin static IDs.

## Generative AI Service

In Shared Components, select the existing Generative AI Service:

- Provider: OpenAI
- Service name: `OPEN AI`
- Static ID: `OPENAI`
- Model: `gpt-5.4`
- Credential: an APEX credential stored outside this repository
- Temperature: low/conservative
- Secrets: never store in `AIPA_APP_SETTINGS`

Set `OPEN AI` as the application's default Generative AI Service, or select it explicitly in the Procurement Assistant Agent. The Agent cannot execute until one of these settings is present.

## Procurement Assistant Agent

Create a Shared Component AI Agent:

- Name: Procurement Assistant Agent
- Static ID: `procurement_assistant_agent`
- Service: `OPEN AI` (`OPENAI`), or the application default after it has been set to that service
- Temperature: `0.1`
- Response format: Text, required by the native Show AI Assistant action
- Response content: include summary, findings, risk level, recommended action, explanation, missing information, approval route, tools used, and whether confirmation is required

System prompt:

```text
You are the Procurement Assistant Agent for AI Procurement Agents.
Use application tools for all purchase request data, policy findings, approval routing, and workflow actions.
Never claim a policy result until the policy findings tool has been called.
Never submit, approve, reject, or request changes unless the user explicitly confirms the action.
Business rules come from deterministic PL/SQL packages. Distinguish deterministic findings from AI interpretation.
Return a concise response with the summary, findings, risk level, recommended action, explanation, missing information, approval route, tools used, and whether confirmation is required.
```

## Required Tools

All tools use execution point **On Demand**.

### get_purchase_request_context

- Type: Retrieve Data, or Server-side Code returning JSON
- Parameter: `purchase_request_id` number, required
- Purpose: return header, lines, requester, department, vendor, total amount, status, risk, and current approval step
- Server-side implementation:

```plsql
return pk_aipa_agent_orchestration.get_purchase_request_context_json(
    p_purchase_request_id => :purchase_request_id
);
```

### get_policy_findings

- Type: Execute Server-side Code
- Parameter: `purchase_request_id` number, required
- Purpose: return deterministic policy findings

```plsql
return pk_aipa_policy_engine.get_findings_json(
    p_purchase_request_id => :purchase_request_id
);
```

### get_approval_route

- Type: Execute Server-side Code
- Parameter: `purchase_request_id` number, required
- Purpose: calculate and return structured approval steps

```plsql
return pk_aipa_workflow.get_approval_route_json(
    p_purchase_request_id => :purchase_request_id
);
```

### submit_for_approval

- Type: Execute Server-side Code
- Requires confirmation: Yes
- Parameter: `purchase_request_id` number, required

```plsql
pk_aipa_workflow.submit_request(
    p_purchase_request_id => :purchase_request_id
);
return json_object('status' value 'submitted' returning clob);
```

### approve_request

- Type: Execute Server-side Code
- Requires confirmation: Yes
- Parameters: `purchase_request_id` number, `approval_comment` varchar2

```plsql
pk_aipa_workflow.approve_request(
    p_purchase_request_id => :purchase_request_id,
    p_approval_comment => :approval_comment
);
return json_object('status' value 'approved' returning clob);
```

### reject_request

- Type: Execute Server-side Code
- Requires confirmation: Yes
- Parameters: `purchase_request_id` number, `rejection_reason` varchar2

```plsql
pk_aipa_workflow.reject_request(
    p_purchase_request_id => :purchase_request_id,
    p_rejection_reason => :rejection_reason
);
return json_object('status' value 'rejected' returning clob);
```

### request_changes

- Type: Execute Server-side Code
- Requires confirmation: Yes
- Parameters: `purchase_request_id` number, `change_request_comment` varchar2

```plsql
pk_aipa_workflow.request_changes(
    p_purchase_request_id => :purchase_request_id,
    p_change_request_comment => :change_request_comment
);
return json_object('status' value 'changes_requested' returning clob);
```

### show_approval_preview

- Type: Execute Client-side Code
- Requires confirmation: No
- Purpose: open an inline drawer or modal showing the generated recommendation before user confirmation
- Parameters: `purchase_request_id` number, `recommendation_json` clob
- Client behavior: render the summary, findings, route, and action in an APEX modal or drawer region.

## Confirmation Text

Use clear confirmation prompts:

- Submit: "Submit this purchase request for approval?"
- Approve: "Approve the current approval step?"
- Reject: "Reject this purchase request?"
- Request changes: "Request changes from the requester?"

## Mock Mode

When `AIPA_APP_SETTINGS.MOCK_MODE_ENABLED = 'Y'`, use `PK_AIPA_AGENT_ORCHESTRATION.run_ai_review` from page buttons or demo scripts. Mock mode records the same audit concepts as live mode: run, messages, tool calls, and recommendation.
