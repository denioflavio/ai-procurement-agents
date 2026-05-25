prompt Creating AI Procurement Agents PL/SQL packages

create or replace package pk_aipa_policy_engine as
    function get_findings_json(p_purchase_request_id in number) return clob;
    function get_risk_level(p_purchase_request_id in number) return varchar2;
end pk_aipa_policy_engine;
/

create or replace package body pk_aipa_policy_engine as
    function get_findings_json(p_purchase_request_id in number) return clob is
        l_json clob;
    begin
        with pr as (
            select r.purchase_request_id,
                   r.total_amount,
                   r.business_justification,
                   r.vendor_id,
                   v.vendor_status,
                   v.risk_level vendor_risk_level
              from aipa_purchase_requests r
              left join aipa_vendors v on v.vendor_id = r.vendor_id
             where r.purchase_request_id = p_purchase_request_id
        ),
        findings as (
            select 'MISSING_VENDOR' finding_code,
                   'HIGH' severity,
                   'The request has no selected vendor.' finding_text,
                   'Select an approved vendor before submission.' recommended_resolution
              from pr
             where vendor_id is null
            union all
            select 'VENDOR_NOT_APPROVED',
                   'HIGH',
                   'The selected vendor is not approved.',
                   'Route the request to Procurement for vendor review.'
              from pr
             where vendor_status <> 'APPROVED'
            union all
            select 'HIGH_RISK_VENDOR',
                   'HIGH',
                   'The selected vendor is classified as high risk.',
                   'Require Finance and Procurement leadership approval.'
              from pr
             where vendor_risk_level = 'HIGH'
            union all
            select 'LARGE_AMOUNT',
                   'MEDIUM',
                   'The request amount is above the standard manager approval threshold.',
                   'Include Finance approval in the route.'
              from pr
             where total_amount >= 10000
            union all
            select 'MISSING_JUSTIFICATION',
                   'MEDIUM',
                   'The business justification is missing or too short.',
                   'Add a clear business justification before approval.'
              from pr
             where length(trim(nvl(business_justification, ''))) < 25
            union all
            select 'RESTRICTED_CATEGORY',
                   'HIGH',
                   'One or more request lines use a restricted category.',
                   'Attach business justification and route for Procurement approval.'
              from pr
             where exists (
                   select 1
                     from aipa_purchase_request_lines l
                    where l.purchase_request_id = pr.purchase_request_id
                      and upper(l.category) in ('LEGAL','SECURITY','AI SERVICES')
             )
        )
        select json_arrayagg(
                   json_object(
                       'finding_code' value finding_code,
                       'severity' value severity,
                       'finding_text' value finding_text,
                       'recommended_resolution' value recommended_resolution
                   returning clob)
               returning clob)
          into l_json
          from findings;

        return coalesce(l_json, '[]');
    end get_findings_json;

    function get_risk_level(p_purchase_request_id in number) return varchar2 is
        l_findings clob := get_findings_json(p_purchase_request_id => p_purchase_request_id);
        l_high number;
        l_medium number;
    begin
        select count(*)
          into l_high
          from json_table(l_findings, '$[*]' columns severity varchar2(10) path '$.severity')
         where severity = 'HIGH';

        select count(*)
          into l_medium
          from json_table(l_findings, '$[*]' columns severity varchar2(10) path '$.severity')
         where severity = 'MEDIUM';

        if l_high > 0 then
            return 'HIGH';
        elsif l_medium > 0 then
            return 'MEDIUM';
        else
            return 'LOW';
        end if;
    end get_risk_level;
end pk_aipa_policy_engine;
/

show errors

create or replace package pk_aipa_workflow as
    function create_request(
        p_requester_id in number,
        p_department_id in number,
        p_vendor_id in number,
        p_title in varchar2,
        p_business_justification in varchar2
    ) return number;

    procedure refresh_approval_route(p_purchase_request_id in number);
    function get_approval_route_json(p_purchase_request_id in number) return clob;
    procedure submit_request(p_purchase_request_id in number);
    procedure approve_request(p_purchase_request_id in number, p_approval_comment in varchar2);
    procedure reject_request(p_purchase_request_id in number, p_rejection_reason in varchar2);
    procedure request_changes(p_purchase_request_id in number, p_change_request_comment in varchar2);
end pk_aipa_workflow;
/

create or replace package body pk_aipa_workflow as
    procedure assert_status(p_purchase_request_id in number, p_allowed_statuses in varchar2) is
        l_status aipa_purchase_requests.status%type;
    begin
        select status
          into l_status
          from aipa_purchase_requests
         where purchase_request_id = p_purchase_request_id
         for update;

        if instr(':' || p_allowed_statuses || ':', ':' || l_status || ':') = 0 then
            raise_application_error(-20001, 'Invalid workflow transition from status ' || l_status || '.');
        end if;
    exception
        when no_data_found then
            raise_application_error(-20002, 'Purchase request not found.');
    end assert_status;

    function create_request(
        p_requester_id in number,
        p_department_id in number,
        p_vendor_id in number,
        p_title in varchar2,
        p_business_justification in varchar2
    ) return number is
        l_id number;
    begin
        insert into aipa_purchase_requests (
            request_number, requester_id, department_id, vendor_id, title, business_justification
        ) values (
            'PR-' || to_char(1000 + aipa_purchase_requests_seq.nextval),
            p_requester_id, p_department_id, p_vendor_id, p_title, p_business_justification
        )
        returning purchase_request_id into l_id;

        return l_id;
    end create_request;

    procedure refresh_approval_route(p_purchase_request_id in number) is
        l_risk aipa_purchase_requests.risk_level%type;
    begin
        l_risk := pk_aipa_policy_engine.get_risk_level(p_purchase_request_id => p_purchase_request_id);

        update aipa_purchase_requests
           set risk_level = l_risk,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id;

        delete from aipa_approval_steps
         where purchase_request_id = p_purchase_request_id
           and status = 'PENDING_APPROVAL';

        insert into aipa_approval_steps (purchase_request_id, step_order, approver_id)
        select p_purchase_request_id,
               row_number() over (order by r.step_order, r.approval_rule_id),
               r.approver_id
          from aipa_approval_rules r
          join aipa_purchase_requests pr on pr.purchase_request_id = p_purchase_request_id
         where r.is_active = 'Y'
           and pr.total_amount >= r.min_amount
           and (r.max_amount is null or pr.total_amount <= r.max_amount)
           and (r.department_id is null or r.department_id = pr.department_id)
           and (r.risk_level is null or r.risk_level = l_risk)
         order by r.step_order, r.approval_rule_id;

        if sql%rowcount = 0 then
            insert into aipa_approval_steps (purchase_request_id, step_order, approver_id)
            select p_purchase_request_id, 1, employee_id
              from aipa_employees
             where approval_limit = (select max(approval_limit) from aipa_employees where is_active = 'Y')
               and rownum = 1;
        end if;
    end refresh_approval_route;

    function get_approval_route_json(p_purchase_request_id in number) return clob is
        l_json clob;
    begin
        refresh_approval_route(p_purchase_request_id => p_purchase_request_id);

        select json_arrayagg(
                   json_object(
                       'step_order' value s.step_order,
                       'approver_name' value e.full_name,
                       'approver_email' value e.email,
                       'status' value s.status
                   returning clob)
                   order by s.step_order
               returning clob)
          into l_json
          from aipa_approval_steps s
          join aipa_employees e on e.employee_id = s.approver_id
         where s.purchase_request_id = p_purchase_request_id;

        return coalesce(l_json, '[]');
    end get_approval_route_json;

    procedure submit_request(p_purchase_request_id in number) is
    begin
        assert_status(p_purchase_request_id => p_purchase_request_id, p_allowed_statuses => 'DRAFT:AI_REVIEWED:CHANGES_REQUESTED');
        refresh_approval_route(p_purchase_request_id => p_purchase_request_id);

        update aipa_purchase_requests
           set status = 'PENDING_APPROVAL',
               submitted_at = systimestamp,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id;
    end submit_request;

    procedure approve_request(p_purchase_request_id in number, p_approval_comment in varchar2) is
        l_step_id number;
        l_remaining number;
    begin
        assert_status(p_purchase_request_id => p_purchase_request_id, p_allowed_statuses => 'PENDING_APPROVAL:SUBMITTED');

        select approval_step_id
          into l_step_id
          from (
                select approval_step_id
                  from aipa_approval_steps
                 where purchase_request_id = p_purchase_request_id
                   and status = 'PENDING_APPROVAL'
                 order by step_order
          )
         where rownum = 1;

        update aipa_approval_steps
           set status = 'APPROVED',
               action_comment = p_approval_comment,
               acted_at = systimestamp,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where approval_step_id = l_step_id;

        select count(*)
          into l_remaining
          from aipa_approval_steps
         where purchase_request_id = p_purchase_request_id
           and status = 'PENDING_APPROVAL';

        if l_remaining = 0 then
            update aipa_purchase_requests
               set status = 'APPROVED',
                   updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
                   updated_at = systimestamp
             where purchase_request_id = p_purchase_request_id;
        end if;
    exception
        when no_data_found then
            raise_application_error(-20003, 'No pending approval step found.');
    end approve_request;

    procedure reject_request(p_purchase_request_id in number, p_rejection_reason in varchar2) is
    begin
        assert_status(p_purchase_request_id => p_purchase_request_id, p_allowed_statuses => 'PENDING_APPROVAL:SUBMITTED');

        update aipa_approval_steps
           set status = 'REJECTED',
               action_comment = p_rejection_reason,
               acted_at = systimestamp,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where approval_step_id = (
               select approval_step_id
                 from (
                       select approval_step_id
                         from aipa_approval_steps
                        where purchase_request_id = p_purchase_request_id
                          and status = 'PENDING_APPROVAL'
                        order by step_order
                 )
                where rownum = 1
         );

        update aipa_purchase_requests
           set status = 'REJECTED',
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id;
    end reject_request;

    procedure request_changes(p_purchase_request_id in number, p_change_request_comment in varchar2) is
    begin
        assert_status(p_purchase_request_id => p_purchase_request_id, p_allowed_statuses => 'PENDING_APPROVAL:SUBMITTED:AI_REVIEWED');

        update aipa_approval_steps
           set status = 'CHANGES_REQUESTED',
               action_comment = p_change_request_comment,
               acted_at = systimestamp,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id
           and status = 'PENDING_APPROVAL';

        update aipa_purchase_requests
           set status = 'CHANGES_REQUESTED',
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id;
    end request_changes;
end pk_aipa_workflow;
/

show errors

create or replace package pk_aipa_llm_provider as
    function is_mock_mode return boolean;
    function generate_mock_recommendation(p_purchase_request_id in number) return clob;
end pk_aipa_llm_provider;
/

create or replace package body pk_aipa_llm_provider as
    function setting(p_name in varchar2, p_default in varchar2) return varchar2 is
        l_value aipa_app_settings.setting_value%type;
    begin
        select setting_value into l_value from aipa_app_settings where setting_name = p_name;
        return coalesce(l_value, p_default);
    exception
        when no_data_found then
            return p_default;
    end setting;

    function is_mock_mode return boolean is
    begin
        return upper(setting(p_name => 'MOCK_MODE_ENABLED', p_default => 'Y')) = 'Y';
    end is_mock_mode;

    function generate_mock_recommendation(p_purchase_request_id in number) return clob is
        l_findings clob;
        l_route clob;
        l_risk varchar2(10);
        l_summary varchar2(1000);
    begin
        l_findings := pk_aipa_policy_engine.get_findings_json(p_purchase_request_id => p_purchase_request_id);
        l_route := pk_aipa_workflow.get_approval_route_json(p_purchase_request_id => p_purchase_request_id);
        l_risk := pk_aipa_policy_engine.get_risk_level(p_purchase_request_id => p_purchase_request_id);

        select 'Review ' || request_number || ': ' || title || ' for ' || to_char(total_amount, 'FM999G999G990D00')
          into l_summary
          from aipa_purchase_requests
         where purchase_request_id = p_purchase_request_id;

        return json_object(
            'summary' value l_summary,
            'findings' value l_findings format json,
            'risk_level' value l_risk,
            'recommended_action' value case when l_risk = 'HIGH' then 'REQUEST_CHANGES_OR_ROUTE_FOR_FINANCE' else 'SUBMIT_FOR_APPROVAL' end,
            'explanation' value 'Mock mode used deterministic policy findings and approval routing from PL/SQL packages.',
            'missing_information' value '[]' format json,
            'approval_route' value l_route format json,
            'tool_calls_used' value '["get_purchase_request_context","get_policy_findings","get_approval_route"]' format json,
            'requires_confirmation' value case when l_risk = 'HIGH' then 'true' else 'false' end format json
        returning clob);
    end generate_mock_recommendation;
end pk_aipa_llm_provider;
/

show errors

create or replace package pk_aipa_agent_orchestration as
    function get_purchase_request_context_json(p_purchase_request_id in number) return clob;
    function record_run_start(p_purchase_request_id in number, p_agent_static_id in varchar2, p_prompt in clob) return number;
    procedure record_tool_call(p_agent_run_id in number, p_tool_name in varchar2, p_parameters_json in clob, p_result_json in clob, p_status in varchar2 default 'SUCCEEDED');
    procedure record_message(p_agent_run_id in number, p_message_role in varchar2, p_message_text in clob, p_message_json in clob default null);
    function run_ai_review(p_purchase_request_id in number) return clob;
    function get_latest_recommendation_json(p_purchase_request_id in number) return clob;
end pk_aipa_agent_orchestration;
/

create or replace package body pk_aipa_agent_orchestration as
    function get_purchase_request_context_json(p_purchase_request_id in number) return clob is
        l_json clob;
    begin
        select json_object(
                   'purchase_request_id' value pr.purchase_request_id,
                   'request_number' value pr.request_number,
                   'title' value pr.title,
                   'status' value pr.status,
                   'risk_level' value pr.risk_level,
                   'total_amount' value pr.total_amount,
                   'currency_code' value pr.currency_code,
                   'requester' value e.full_name,
                   'department' value d.department_name,
                   'vendor' value v.vendor_name,
                   'current_approval_step' value (
                       select min(step_order)
                         from aipa_approval_steps s
                        where s.purchase_request_id = pr.purchase_request_id
                          and s.status = 'PENDING_APPROVAL'
                   ),
                   'lines' value (
                       select json_arrayagg(
                                  json_object(
                                      'line_number' value l.line_number,
                                      'item_description' value l.item_description,
                                      'category' value l.category,
                                      'quantity' value l.quantity,
                                      'unit_price' value l.unit_price,
                                      'line_amount' value l.line_amount
                                  returning clob)
                                  order by l.line_number
                              returning clob)
                         from aipa_purchase_request_lines l
                        where l.purchase_request_id = pr.purchase_request_id
                   ) format json
               returning clob)
          into l_json
          from aipa_purchase_requests pr
          join aipa_employees e on e.employee_id = pr.requester_id
          join aipa_departments d on d.department_id = pr.department_id
          left join aipa_vendors v on v.vendor_id = pr.vendor_id
         where pr.purchase_request_id = p_purchase_request_id;

        return l_json;
    end get_purchase_request_context_json;

    function record_run_start(p_purchase_request_id in number, p_agent_static_id in varchar2, p_prompt in clob) return number is
        l_run_id number;
        l_mode varchar2(20);
    begin
        if pk_aipa_llm_provider.is_mock_mode then
            l_mode := 'MOCK';
        else
            l_mode := 'LIVE';
        end if;

        insert into aipa_agent_runs (
            purchase_request_id, agent_static_id, status, model_name, provider_name, mode, prompt
        ) values (
            p_purchase_request_id, p_agent_static_id, 'STARTED', 'GPT-5.5', 'OpenAI',
            l_mode,
            p_prompt
        )
        returning agent_run_id into l_run_id;

        return l_run_id;
    end record_run_start;

    procedure record_tool_call(p_agent_run_id in number, p_tool_name in varchar2, p_parameters_json in clob, p_result_json in clob, p_status in varchar2 default 'SUCCEEDED') is
    begin
        insert into aipa_agent_tool_calls (
            agent_run_id, tool_name, status, parameters_json, result_json, ended_at, duration_ms
        ) values (
            p_agent_run_id, p_tool_name, p_status, p_parameters_json, p_result_json, systimestamp, 1
        );
    end record_tool_call;

    procedure record_message(p_agent_run_id in number, p_message_role in varchar2, p_message_text in clob, p_message_json in clob default null) is
    begin
        insert into aipa_agent_messages (agent_run_id, message_role, message_text, message_json)
        values (p_agent_run_id, p_message_role, p_message_text, p_message_json);
    end record_message;

    function run_ai_review(p_purchase_request_id in number) return clob is
        l_run_id number;
        l_context clob;
        l_findings clob;
        l_route clob;
        l_response clob;
        l_risk varchar2(10);
    begin
        l_run_id := record_run_start(
            p_purchase_request_id => p_purchase_request_id,
            p_agent_static_id => 'procurement_assistant_agent',
            p_prompt => 'Run deterministic procurement review for purchase request ' || p_purchase_request_id
        );

        l_context := get_purchase_request_context_json(p_purchase_request_id => p_purchase_request_id);
        record_tool_call(l_run_id, 'get_purchase_request_context', json_object('purchase_request_id' value p_purchase_request_id returning clob), l_context, 'MOCKED');

        l_findings := pk_aipa_policy_engine.get_findings_json(p_purchase_request_id => p_purchase_request_id);
        record_tool_call(l_run_id, 'get_policy_findings', json_object('purchase_request_id' value p_purchase_request_id returning clob), l_findings, 'MOCKED');

        l_route := pk_aipa_workflow.get_approval_route_json(p_purchase_request_id => p_purchase_request_id);
        record_tool_call(l_run_id, 'get_approval_route', json_object('purchase_request_id' value p_purchase_request_id returning clob), l_route, 'MOCKED');

        l_response := pk_aipa_llm_provider.generate_mock_recommendation(p_purchase_request_id => p_purchase_request_id);
        l_risk := json_value(l_response, '$.risk_level');

        insert into aipa_agent_recommendations (
            agent_run_id, purchase_request_id, summary, risk_level, recommended_action, explanation, recommendation_json, requires_confirmation
        ) values (
            l_run_id,
            p_purchase_request_id,
            json_value(l_response, '$.summary'),
            l_risk,
            json_value(l_response, '$.recommended_action'),
            json_value(l_response, '$.explanation'),
            l_response,
            case when json_value(l_response, '$.requires_confirmation') = 'true' then 'Y' else 'N' end
        );

        update aipa_purchase_requests
           set status = case when status = 'DRAFT' then 'AI_REVIEWED' else status end,
               risk_level = l_risk,
               updated_by = coalesce(sys_context('APEX$SESSION','APP_USER'), user),
               updated_at = systimestamp
         where purchase_request_id = p_purchase_request_id;

        record_message(l_run_id, 'ASSISTANT', json_value(l_response, '$.summary'), l_response);

        update aipa_agent_runs
           set status = 'MOCKED',
               response = l_response,
               ended_at = systimestamp,
               duration_ms = extract(second from (systimestamp - started_at)) * 1000
         where agent_run_id = l_run_id;

        return l_response;
    exception
        when others then
            if l_run_id is not null then
                update aipa_agent_runs
                   set status = 'FAILED',
                       error_message = sqlerrm,
                       ended_at = systimestamp
                 where agent_run_id = l_run_id;
            end if;
            raise;
    end run_ai_review;

    function get_latest_recommendation_json(p_purchase_request_id in number) return clob is
        l_json clob;
    begin
        select recommendation_json
          into l_json
          from (
                select recommendation_json
                  from aipa_agent_recommendations
                 where purchase_request_id = p_purchase_request_id
                 order by created_at desc
          )
         where rownum = 1;

        return l_json;
    exception
        when no_data_found then
            return json_object(
                'summary' value 'No AI review has been run yet.',
                'findings' value '[]' format json,
                'risk_level' value 'LOW',
                'recommended_action' value 'RUN_AI_REVIEW',
                'explanation' value 'Run AI Review to create a deterministic recommendation.',
                'missing_information' value '[]' format json,
                'approval_route' value '[]' format json,
                'tool_calls_used' value '[]' format json,
                'requires_confirmation' value 'false' format json
            returning clob);
    end get_latest_recommendation_json;
end pk_aipa_agent_orchestration;
/

show errors

create or replace package pk_aipa_seed as
    procedure reset_demo_data;
    procedure load_demo_data;
end pk_aipa_seed;
/

create or replace package body pk_aipa_seed as
    procedure reset_demo_data is
    begin
        delete from aipa_agent_recommendations;
        delete from aipa_agent_tool_calls;
        delete from aipa_agent_messages;
        delete from aipa_agent_runs;
        delete from aipa_approval_steps;
        delete from aipa_purchase_request_lines;
        delete from aipa_purchase_requests;
        delete from aipa_approval_rules;
        delete from aipa_procurement_policies;
        delete from aipa_vendors;
        delete from aipa_employees;
        delete from aipa_departments;
        delete from aipa_app_settings;
        commit;
    end reset_demo_data;

    procedure load_demo_data is
        l_ops number;
        l_fin number;
        l_it number;
        l_alex number;
        l_maya number;
        l_finance number;
        l_procurement number;
        l_v1 number;
        l_v2 number;
        l_v3 number;
        l_pr number;
    begin
        reset_demo_data;

        insert into aipa_departments (department_code, department_name, cost_center) values ('OPS','Operations','100') returning department_id into l_ops;
        insert into aipa_departments (department_code, department_name, cost_center) values ('FIN','Finance','200') returning department_id into l_fin;
        insert into aipa_departments (department_code, department_name, cost_center) values ('IT','Information Technology','300') returning department_id into l_it;

        insert into aipa_employees (employee_number, full_name, email, job_title, department_id, approval_limit) values ('E100','Alex Morgan','alex.morgan@example.com','Requester',l_ops,1000) returning employee_id into l_alex;
        insert into aipa_employees (employee_number, full_name, email, job_title, department_id, approval_limit) values ('E200','Maya Chen','maya.chen@example.com','Operations Manager',l_ops,10000) returning employee_id into l_maya;
        insert into aipa_employees (employee_number, full_name, email, job_title, department_id, approval_limit) values ('E300','Riley Patel','riley.patel@example.com','Finance Approver',l_fin,50000) returning employee_id into l_finance;
        insert into aipa_employees (employee_number, full_name, email, job_title, department_id, approval_limit) values ('E400','Jordan Lee','jordan.lee@example.com','Procurement Lead',l_fin,100000) returning employee_id into l_procurement;

        insert into aipa_vendors (vendor_name, vendor_status, risk_level, tax_identifier) values ('Northwind Office Supply','APPROVED','LOW','US-100') returning vendor_id into l_v1;
        insert into aipa_vendors (vendor_name, vendor_status, risk_level, tax_identifier) values ('Contoso AI Services','APPROVED','HIGH','US-200') returning vendor_id into l_v2;
        insert into aipa_vendors (vendor_name, vendor_status, risk_level, tax_identifier) values ('Fabrikam Legal Partners','PENDING_REVIEW','MEDIUM','US-300') returning vendor_id into l_v3;

        insert into aipa_procurement_policies (policy_code, policy_name, severity, rule_type, threshold_amount, policy_text, recommended_resolution)
        values ('POL_VENDOR_REQUIRED','Vendor required','HIGH','VENDOR_REQUIRED',null,'A purchase request must identify an approved vendor before submission.','Select an approved vendor.');
        insert into aipa_procurement_policies (policy_code, policy_name, severity, rule_type, threshold_amount, policy_text, recommended_resolution)
        values ('POL_FINANCE_10K','Finance review above 10K','MEDIUM','AMOUNT_THRESHOLD',10000,'Requests at or above 10,000 require Finance approval.','Route to Finance.');
        insert into aipa_procurement_policies (policy_code, policy_name, severity, rule_type, category, policy_text, recommended_resolution)
        values ('POL_RESTRICTED_CATEGORY','Restricted category review','HIGH','CATEGORY','AI SERVICES','AI Services, Legal, and Security purchases require Procurement review.','Add Procurement approval and justification.');

        insert into aipa_approval_rules (rule_name, min_amount, max_amount, department_id, approver_id, step_order) values ('Department manager',0,9999,l_ops,l_maya,1);
        insert into aipa_approval_rules (rule_name, min_amount, max_amount, approver_id, step_order) values ('Finance amount approval',10000,49999,l_finance,2);
        insert into aipa_approval_rules (rule_name, min_amount, risk_level, approver_id, step_order) values ('High risk procurement review',0,'HIGH',l_procurement,1);

        insert into aipa_app_settings (setting_name, setting_value, setting_description) values ('MOCK_MODE_ENABLED','Y','Use deterministic mock recommendations for public demos.');
        insert into aipa_app_settings (setting_name, setting_value, setting_description) values ('MODEL_NAME','GPT-5.5','Default model name for live mode documentation.');
        insert into aipa_app_settings (setting_name, setting_value, setting_description) values ('PROVIDER_NAME','OpenAI','Default live provider.');
        insert into aipa_app_settings (setting_name, setting_value, setting_description) values ('CREDENTIAL_STATIC_ID','','Optional APEX credential static ID. Secrets are never stored here.');

        insert into aipa_purchase_requests (request_number, requester_id, department_id, vendor_id, title, business_justification, status, total_amount)
        values ('PR-1001',l_alex,l_ops,l_v1,'Ergonomic office chairs','Replace broken chairs for the operations team.', 'DRAFT', 0) returning purchase_request_id into l_pr;
        insert into aipa_purchase_request_lines (purchase_request_id, line_number, item_description, category, quantity, unit_price) values (l_pr,1,'Ergonomic office chair','OFFICE',8,450);

        insert into aipa_purchase_requests (request_number, requester_id, department_id, vendor_id, title, business_justification, status, total_amount)
        values ('PR-1002',l_alex,l_it,l_v2,'AI document extraction pilot','Pilot AI services for invoice intake automation.', 'DRAFT', 0) returning purchase_request_id into l_pr;
        insert into aipa_purchase_request_lines (purchase_request_id, line_number, item_description, category, quantity, unit_price) values (l_pr,1,'AI extraction subscription','AI SERVICES',1,18000);
        l_pr := l_pr;
        declare
            l_response clob;
        begin
            l_response := pk_aipa_agent_orchestration.run_ai_review(p_purchase_request_id => l_pr);
            pk_aipa_workflow.submit_request(p_purchase_request_id => l_pr);
        end;

        insert into aipa_purchase_requests (request_number, requester_id, department_id, vendor_id, title, business_justification, status, total_amount)
        values ('PR-1003',l_alex,l_ops,l_v3,'Contract review package','Need legal review package for supplier contract renewal.', 'DRAFT', 0) returning purchase_request_id into l_pr;
        insert into aipa_purchase_request_lines (purchase_request_id, line_number, item_description, category, quantity, unit_price) values (l_pr,1,'Legal review retainer','LEGAL',1,7500);
        declare
            l_response clob;
        begin
            l_response := pk_aipa_agent_orchestration.run_ai_review(p_purchase_request_id => l_pr);
        end;

        commit;
    end load_demo_data;
end pk_aipa_seed;
/

show errors
