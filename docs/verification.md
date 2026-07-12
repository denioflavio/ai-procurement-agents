# Verification

Run from the public repository root:

```bash
scripts/check-apexlang.sh
```

Expected result:

```text
APEXLANG_LOCAL_CHECK_OK
APEXLANG_COMPILER_TRUTH_AUDIT_OK
```

Database verification after installing into `AIPA`:

```sql
select status, count(*) from aipa_purchase_requests group by status;

declare
    l_response clob;
begin
    l_response := pk_aipa_agent_orchestration.run_ai_review(1);
    dbms_output.put_line(dbms_lob.substr(l_response, 4000, 1));
    commit;
end;
/
```
