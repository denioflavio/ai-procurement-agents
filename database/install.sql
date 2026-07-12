prompt Installing AI Procurement Agents database objects in the current schema

whenever sqlerror exit sql.sqlcode rollback

alter session disable parallel dml;

@@10_tables.sql
@@20_packages.sql
@@30_seed.sql

prompt Installation complete.
