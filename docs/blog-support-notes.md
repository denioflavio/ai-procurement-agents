# Blog Support Notes

This demo supports a post about Oracle APEX AI Agents by showing a workflow that moves from insight to action.

The app demonstrates:

- AI Agents as native APEX Shared Components.
- Agentic workflow instead of general-purpose chat.
- Reasoning over intent such as "Can this be submitted?" or "Why is this high risk?"
- Tool-based access to application capabilities.
- Retrieve Data-style context access for request data.
- Server-side tools that call deterministic PL/SQL packages.
- Client-side preview before sensitive actions.
- Human confirmation before submit, approve, reject, or request changes.
- Business logic in PL/SQL and state in Oracle Database.
- APEX controlling what the model can see and do.

Suggested demo prompts:

- What should I do next with PR-1003?
- Why is this purchase high risk?
- Can PR-1002 be submitted for approval?
- What policy issues are blocking this request?
- Summarize PR-1002 for Finance approval.
- Approve this request if there are no high-risk findings.

The important teaching point is that the model does not own procurement rules. It interprets intent, calls controlled tools, explains deterministic results, and asks for confirmation before changing state.
