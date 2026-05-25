prompt Creating AIPA schema when run as an administrative user

declare
    l_count number;
begin
    select count(*)
      into l_count
      from dba_users
     where username = 'AIPA';

    if l_count = 0 then
        execute immediate q'[
            create user AIPA identified by "ChangeMe_See_README_26"
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

prompt AIPA schema is ready. Change the password before production use.
