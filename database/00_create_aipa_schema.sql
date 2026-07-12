prompt Creating AIPA schema when run as an administrative user

whenever sqlerror exit sql.sqlcode rollback

set verify off

accept aipa_password char prompt 'Temporary password for AIPA: ' hide

declare
    l_count number;
begin
    select count(*)
      into l_count
      from dba_users
     where username = 'AIPA';

    if l_count = 0 then
        execute immediate q'[
            create user AIPA identified by "&&aipa_password"
            default tablespace DATA
            temporary tablespace TEMP
            quota unlimited on DATA
        ]';
    end if;
end;
/

grant create session to AIPA;
grant create table to AIPA;
grant create view to AIPA;
grant create sequence to AIPA;
grant create procedure to AIPA;
grant create trigger to AIPA;
grant create type to AIPA;

undefine aipa_password

prompt AIPA schema is ready. Keep its password outside the repository.
