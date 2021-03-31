-- datahub_schema."columns" source
CREATE
OR REPLACE VIEW datahub_schema."columns" AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"."',
                columns.column_name,
                '"'
            ) AS concat
    ) AS column_reference,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.columns_privileges source
CREATE
OR REPLACE VIEW datahub_schema.columns_privileges AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"."',
                columns.column_name,
                '"'
            ) AS concat
    ) AS column_reference,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.constraint_column_usage source
CREATE
OR REPLACE VIEW datahub_schema.constraint_column_usage AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"."',
                columns.column_name,
                '"'
            ) AS concat
    ) AS column_reference,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.constraint_table_usage source
CREATE
OR REPLACE VIEW datahub_schema.constraint_table_usage AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.event_invocation_logs source
CREATE
OR REPLACE VIEW datahub_schema.event_invocation_logs AS
SELECT
    event_invocation_logs.id,
    event_invocation_logs.event_id,
    event_invocation_logs.status,
    event_invocation_logs.request,
    event_invocation_logs.response,
    event_invocation_logs.created_at
FROM
    hdb_catalog.event_invocation_logs;

-- datahub_schema.event_log source
CREATE
OR REPLACE VIEW datahub_schema.event_log AS
SELECT
    event_log.id,
    event_log.schema_name,
    event_log.table_name,
    event_log.trigger_name,
    event_log.payload,
    event_log.delivered,
    event_log.error,
    event_log.tries,
    event_log.created_at,
    event_log.locked,
    event_log.next_retry_at,
    event_log.archived
FROM
    hdb_catalog.event_log;

-- datahub_schema.event_triggers source
CREATE
OR REPLACE VIEW datahub_schema.event_triggers AS
SELECT
    event_triggers.name,
    event_triggers.type,
    event_triggers.schema_name,
    event_triggers.table_name,
    event_triggers.configuration,
    event_triggers.comment
FROM
    hdb_catalog.event_triggers;

-- datahub_schema.hdb_action source
CREATE
OR REPLACE VIEW datahub_schema.hdb_action AS
SELECT
    hdb_action.action_name,
    hdb_action.action_defn,
    hdb_action.comment,
    hdb_action.is_system_defined
FROM
    hdb_catalog.hdb_action;

-- datahub_schema.hdb_action_log source
CREATE
OR REPLACE VIEW datahub_schema.hdb_action_log AS
SELECT
    hdb_action_log.id,
    hdb_action_log.action_name,
    hdb_action_log.input_payload,
    hdb_action_log.request_headers,
    hdb_action_log.session_variables,
    hdb_action_log.response_payload,
    hdb_action_log.errors,
    hdb_action_log.created_at,
    hdb_action_log.response_received_at,
    hdb_action_log.status
FROM
    hdb_catalog.hdb_action_log;

-- datahub_schema.hdb_action_permission source
CREATE
OR REPLACE VIEW datahub_schema.hdb_action_permission AS
SELECT
    hdb_action_permission.action_name,
    hdb_action_permission.role_name,
    hdb_action_permission.definition,
    hdb_action_permission.comment
FROM
    hdb_catalog.hdb_action_permission;

-- datahub_schema.hdb_computed_field source
CREATE
OR REPLACE VIEW datahub_schema.hdb_computed_field AS
SELECT
    hdb_computed_field.table_schema,
    hdb_computed_field.table_name,
    hdb_computed_field.computed_field_name,
    hdb_computed_field.definition,
    hdb_computed_field.comment
FROM
    hdb_catalog.hdb_computed_field;

-- datahub_schema.hdb_cron_event_invocation_logs source
CREATE
OR REPLACE VIEW datahub_schema.hdb_cron_event_invocation_logs AS
SELECT
    hdb_cron_event_invocation_logs.id,
    hdb_cron_event_invocation_logs.event_id,
    hdb_cron_event_invocation_logs.status,
    hdb_cron_event_invocation_logs.request,
    hdb_cron_event_invocation_logs.response,
    hdb_cron_event_invocation_logs.created_at
FROM
    hdb_catalog.hdb_cron_event_invocation_logs;

-- datahub_schema.hdb_cron_events source
CREATE
OR REPLACE VIEW datahub_schema.hdb_cron_events AS
SELECT
    hdb_cron_events.id,
    hdb_cron_events.trigger_name,
    hdb_cron_events.scheduled_time,
    hdb_cron_events.status,
    hdb_cron_events.tries,
    hdb_cron_events.created_at,
    hdb_cron_events.next_retry_at
FROM
    hdb_catalog.hdb_cron_events;

-- datahub_schema.hdb_cron_triggers source
CREATE
OR REPLACE VIEW datahub_schema.hdb_cron_triggers AS
SELECT
    hdb_cron_triggers.name,
    hdb_cron_triggers.webhook_conf,
    hdb_cron_triggers.cron_schedule,
    hdb_cron_triggers.payload,
    hdb_cron_triggers.retry_conf,
    hdb_cron_triggers.header_conf,
    hdb_cron_triggers.include_in_metadata,
    hdb_cron_triggers.comment
FROM
    hdb_catalog.hdb_cron_triggers;

-- datahub_schema.hdb_custom_types source
CREATE
OR REPLACE VIEW datahub_schema.hdb_custom_types AS
SELECT
    hdb_custom_types.custom_types
FROM
    hdb_catalog.hdb_custom_types;

-- datahub_schema.hdb_function source
CREATE
OR REPLACE VIEW datahub_schema.hdb_function AS
SELECT
    hdb_function.function_schema,
    hdb_function.function_name,
    hdb_function.configuration,
    hdb_function.is_system_defined
FROM
    hdb_catalog.hdb_function;

-- datahub_schema.hdb_permission source
CREATE
OR REPLACE VIEW datahub_schema.hdb_permission AS
SELECT
    hdb_permission.table_schema,
    hdb_permission.table_name,
    hdb_permission.role_name,
    hdb_permission.perm_type,
    hdb_permission.perm_def,
    hdb_permission.comment,
    hdb_permission.is_system_defined
FROM
    hdb_catalog.hdb_permission;

-- datahub_schema.hdb_relationship source
CREATE
OR REPLACE VIEW datahub_schema.hdb_relationship AS
SELECT
    hdb_relationship.table_schema,
    hdb_relationship.table_name,
    hdb_relationship.rel_name,
    hdb_relationship.rel_type,
    hdb_relationship.rel_def,
    hdb_relationship.comment,
    hdb_relationship.is_system_defined
FROM
    hdb_catalog.hdb_relationship;

-- datahub_schema.hdb_remote_relationship source
CREATE
OR REPLACE VIEW datahub_schema.hdb_remote_relationship AS
SELECT
    hdb_remote_relationship.remote_relationship_name,
    hdb_remote_relationship.table_schema,
    hdb_remote_relationship.table_name,
    hdb_remote_relationship.definition
FROM
    hdb_catalog.hdb_remote_relationship;

-- datahub_schema.hdb_scheduled_event_invocation_logs source
CREATE
OR REPLACE VIEW datahub_schema.hdb_scheduled_event_invocation_logs AS
SELECT
    hdb_scheduled_event_invocation_logs.id,
    hdb_scheduled_event_invocation_logs.event_id,
    hdb_scheduled_event_invocation_logs.status,
    hdb_scheduled_event_invocation_logs.request,
    hdb_scheduled_event_invocation_logs.response,
    hdb_scheduled_event_invocation_logs.created_at
FROM
    hdb_catalog.hdb_scheduled_event_invocation_logs;

-- datahub_schema.hdb_scheduled_events source
CREATE
OR REPLACE VIEW datahub_schema.hdb_scheduled_events AS
SELECT
    hdb_scheduled_events.id,
    hdb_scheduled_events.webhook_conf,
    hdb_scheduled_events.scheduled_time,
    hdb_scheduled_events.retry_conf,
    hdb_scheduled_events.payload,
    hdb_scheduled_events.header_conf,
    hdb_scheduled_events.status,
    hdb_scheduled_events.tries,
    hdb_scheduled_events.created_at,
    hdb_scheduled_events.next_retry_at,
    hdb_scheduled_events.comment
FROM
    hdb_catalog.hdb_scheduled_events;

-- datahub_schema.hdb_table source
CREATE
OR REPLACE VIEW datahub_schema.hdb_table AS
SELECT
    hdb_table.table_schema,
    hdb_table.table_name,
    hdb_table.configuration,
    hdb_table.is_system_defined,
    hdb_table.is_enum,
    (
        SELECT
            concat(
                '"',
                hdb_table.table_schema,
                '"."',
                hdb_table.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', hdb_table.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    hdb_catalog.hdb_table;

-- datahub_schema.key_column_usage source
CREATE
OR REPLACE VIEW datahub_schema.key_column_usage AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"."',
                columns.column_name,
                '"'
            ) AS concat
    ) AS column_reference,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.referential_constraints source
CREATE
OR REPLACE VIEW datahub_schema.referential_constraints AS
SELECT
    referential_constraints.constraint_catalog,
    referential_constraints.constraint_schema,
    referential_constraints.constraint_name,
    referential_constraints.unique_constraint_catalog,
    referential_constraints.unique_constraint_schema,
    referential_constraints.unique_constraint_name,
    referential_constraints.match_option,
    referential_constraints.update_rule,
    referential_constraints.delete_rule,
    (
        SELECT
            concat(
                '"',
                referential_constraints.constraint_schema,
                '"."',
                referential_constraints.constraint_name,
                '"'
            ) AS concat
    ) AS constraint_reference,
    (
        SELECT
            concat(
                '"',
                referential_constraints.constraint_schema,
                '"'
            ) AS concat
    ) AS constraint_schema_reference
FROM
    information_schema.referential_constraints
WHERE
    referential_constraints.unique_constraint_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.remote_schemas source
CREATE
OR REPLACE VIEW datahub_schema.remote_schemas AS
SELECT
    remote_schemas.id,
    remote_schemas.name,
    remote_schemas.definition,
    remote_schemas.comment
FROM
    hdb_catalog.remote_schemas;

-- datahub_schema.role_column_grant source
CREATE
OR REPLACE VIEW datahub_schema.role_column_grant AS
SELECT
    columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"."',
                columns.column_name,
                '"'
            ) AS concat
    ) AS column_reference,
    (
        SELECT
            concat(
                '"',
                columns.table_schema,
                '"."',
                columns.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', columns.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.columns
WHERE
    columns.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema."routines" source
CREATE
OR REPLACE VIEW datahub_schema."routines" AS
SELECT
    routines.specific_catalog,
    routines.specific_schema,
    routines.specific_name,
    routines.routine_catalog,
    routines.routine_schema,
    routines.routine_name,
    routines.routine_type,
    routines.module_catalog,
    routines.module_schema,
    routines.module_name,
    routines.udt_catalog,
    routines.udt_schema,
    routines.udt_name,
    routines.data_type,
    routines.character_maximum_length,
    routines.character_octet_length,
    routines.character_set_catalog,
    routines.character_set_schema,
    routines.character_set_name,
    routines.collation_catalog,
    routines.collation_schema,
    routines.collation_name,
    routines.numeric_precision,
    routines.numeric_precision_radix,
    routines.numeric_scale,
    routines.datetime_precision,
    routines.interval_type,
    routines.interval_precision,
    routines.type_udt_catalog,
    routines.type_udt_schema,
    routines.type_udt_name,
    routines.scope_catalog,
    routines.scope_schema,
    routines.scope_name,
    routines.maximum_cardinality,
    routines.dtd_identifier,
    routines.routine_body,
    routines.routine_definition,
    routines.external_name,
    routines.external_language,
    routines.parameter_style,
    routines.is_deterministic,
    routines.sql_data_access,
    routines.is_null_call,
    routines.sql_path,
    routines.schema_level_routine,
    routines.max_dynamic_result_sets,
    routines.is_user_defined_cast,
    routines.is_implicitly_invocable,
    routines.security_type,
    routines.to_sql_specific_catalog,
    routines.to_sql_specific_schema,
    routines.to_sql_specific_name,
    routines.as_locator,
    routines.created,
    routines.last_altered,
    routines.new_savepoint_level,
    routines.is_udt_dependent,
    routines.result_cast_from_data_type,
    routines.result_cast_as_locator,
    routines.result_cast_char_max_length,
    routines.result_cast_char_octet_length,
    routines.result_cast_char_set_catalog,
    routines.result_cast_char_set_schema,
    routines.result_cast_char_set_name,
    routines.result_cast_collation_catalog,
    routines.result_cast_collation_schema,
    routines.result_cast_collation_name,
    routines.result_cast_numeric_precision,
    routines.result_cast_numeric_precision_radix,
    routines.result_cast_numeric_scale,
    routines.result_cast_datetime_precision,
    routines.result_cast_interval_type,
    routines.result_cast_interval_precision,
    routines.result_cast_type_udt_catalog,
    routines.result_cast_type_udt_schema,
    routines.result_cast_type_udt_name,
    routines.result_cast_scope_catalog,
    routines.result_cast_scope_schema,
    routines.result_cast_scope_name,
    routines.result_cast_maximum_cardinality,
    routines.result_cast_dtd_identifier,
    (
        SELECT
            concat(
                '"',
                routines.routine_schema,
                '"."',
                routines.routine_name,
                '"'
            ) AS concat
    ) AS routine_reference,
    (
        SELECT
            concat('"', routines.routine_schema, '"') AS concat
    ) AS routine_schema_reference
FROM
    information_schema.routines
WHERE
    routines.specific_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.schemata source
CREATE
OR REPLACE VIEW datahub_schema.schemata AS
SELECT
    schemata.catalog_name,
    schemata.schema_name,
    schemata.schema_owner,
    schemata.default_character_set_catalog,
    schemata.default_character_set_schema,
    schemata.default_character_set_name,
    schemata.sql_path,
    (
        SELECT
            concat('"', schemata.schema_name, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.schemata;

-- datahub_schema."sequences" source
CREATE
OR REPLACE VIEW datahub_schema."sequences" AS
SELECT
    sequences.sequence_catalog,
    sequences.sequence_schema,
    sequences.sequence_name,
    sequences.data_type,
    sequences.numeric_precision,
    sequences.numeric_precision_radix,
    sequences.numeric_scale,
    sequences.start_value,
    sequences.minimum_value,
    sequences.maximum_value,
    sequences.increment,
    sequences.cycle_option,
    sequences.sequence_schema AS schema_reference
FROM
    information_schema.sequences
WHERE
    sequences.sequence_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.table_constraints source
CREATE
OR REPLACE VIEW datahub_schema.table_constraints AS
SELECT
    table_constraints.constraint_catalog,
    table_constraints.constraint_schema,
    table_constraints.constraint_name,
    table_constraints.table_catalog,
    table_constraints.table_schema,
    table_constraints.table_name,
    table_constraints.constraint_type,
    table_constraints.is_deferrable,
    table_constraints.initially_deferred,
    table_constraints.enforced,
    (
        SELECT
            concat(
                '"',
                table_constraints.table_schema,
                '"."',
                table_constraints.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', table_constraints.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.table_constraints
WHERE
    table_constraints.constraint_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.table_privileges source
CREATE
OR REPLACE VIEW datahub_schema.table_privileges AS
SELECT
    table_privileges.grantor,
    table_privileges.grantee,
    table_privileges.table_catalog,
    table_privileges.table_schema,
    table_privileges.table_name,
    table_privileges.privilege_type,
    table_privileges.is_grantable,
    table_privileges.with_hierarchy,
    (
        SELECT
            concat(
                '"',
                table_privileges.table_schema,
                '"."',
                table_privileges.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', table_privileges.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.table_privileges
WHERE
    table_privileges.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema."tables" source
CREATE
OR REPLACE VIEW datahub_schema."tables" AS
SELECT
    tables.table_catalog,
    tables.table_schema,
    tables.table_name,
    tables.table_type,
    tables.self_referencing_column_name,
    tables.reference_generation,
    tables.user_defined_type_catalog,
    tables.user_defined_type_schema,
    tables.user_defined_type_name,
    tables.is_insertable_into,
    tables.is_typed,
    tables.commit_action,
    (
        SELECT
            concat(
                '"',
                tables.table_schema,
                '"."',
                tables.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', tables.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.tables
WHERE
    tables.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.triggered_update_column source
CREATE
OR REPLACE VIEW datahub_schema.triggered_update_column AS
SELECT
    triggers.trigger_catalog,
    triggers.trigger_schema,
    triggers.trigger_name,
    triggers.event_manipulation,
    triggers.event_object_catalog,
    triggers.event_object_schema,
    triggers.event_object_table,
    triggers.action_order,
    triggers.action_condition,
    triggers.action_statement,
    triggers.action_orientation,
    triggers.action_timing,
    triggers.action_reference_old_table,
    triggers.action_reference_new_table,
    triggers.action_reference_old_row,
    triggers.action_reference_new_row,
    triggers.created,
    (
        SELECT
            concat(
                '"',
                triggers.trigger_schema,
                '"."',
                triggers.trigger_name,
                '"'
            ) AS concat
    ) AS trigger_reference,
    (
        SELECT
            concat('"', triggers.trigger_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.triggers
WHERE
    triggers.trigger_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.triggers source
CREATE
OR REPLACE VIEW datahub_schema.triggers AS
SELECT
    triggers.trigger_catalog,
    triggers.trigger_schema,
    triggers.trigger_name,
    triggers.event_manipulation,
    triggers.event_object_catalog,
    triggers.event_object_schema,
    triggers.event_object_table,
    triggers.action_order,
    triggers.action_condition,
    triggers.action_statement,
    triggers.action_orientation,
    triggers.action_timing,
    triggers.action_reference_old_table,
    triggers.action_reference_new_table,
    triggers.action_reference_old_row,
    triggers.action_reference_new_row,
    triggers.created,
    (
        SELECT
            concat(
                '"',
                triggers.trigger_schema,
                '"."',
                triggers.trigger_name,
                '"'
            ) AS concat
    ) AS trigger_reference,
    (
        SELECT
            concat('"', triggers.trigger_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.triggers
WHERE
    triggers.trigger_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.view_column_usage source
CREATE
OR REPLACE VIEW datahub_schema.view_column_usage AS
SELECT
    view_column_usage.view_catalog,
    view_column_usage.view_schema,
    view_column_usage.view_name,
    view_column_usage.table_catalog,
    view_column_usage.table_schema,
    view_column_usage.table_name,
    view_column_usage.column_name,
    (
        SELECT
            concat(
                '"',
                view_column_usage.view_schema,
                '"."',
                view_column_usage.view_name,
                '"'
            ) AS concat
    ) AS view_reference,
    (
        SELECT
            concat(
                '"',
                view_column_usage.table_schema,
                '"."',
                view_column_usage.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', view_column_usage.view_schema, '"') AS concat
    ) AS view_schema_reference,
    (
        SELECT
            concat('"', view_column_usage.table_schema, '"') AS concat
    ) AS table_schema_reference
FROM
    information_schema.view_column_usage
WHERE
    view_column_usage.view_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.view_routine_usage source
CREATE
OR REPLACE VIEW datahub_schema.view_routine_usage AS
SELECT
    view_routine_usage.table_catalog,
    view_routine_usage.table_schema,
    view_routine_usage.table_name,
    view_routine_usage.specific_catalog,
    view_routine_usage.specific_schema,
    view_routine_usage.specific_name,
    (
        SELECT
            concat(
                '"',
                view_routine_usage.table_schema,
                '"."',
                view_routine_usage.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', view_routine_usage.table_schema, '"') AS concat
    ) AS table_schema_reference
FROM
    information_schema.view_routine_usage
WHERE
    view_routine_usage.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema.view_table_usage source
CREATE
OR REPLACE VIEW datahub_schema.view_table_usage AS
SELECT
    view_table_usage.view_catalog,
    view_table_usage.view_schema,
    view_table_usage.view_name,
    view_table_usage.table_catalog,
    view_table_usage.table_schema,
    view_table_usage.table_name,
    (
        SELECT
            concat(
                '"',
                view_table_usage.view_schema,
                '"."',
                view_table_usage.view_name,
                '"'
            ) AS concat
    ) AS view_reference,
    (
        SELECT
            concat(
                '"',
                view_table_usage.table_schema,
                '"."',
                view_table_usage.table_name,
                '"'
            ) AS concat
    ) AS table_reference,
    (
        SELECT
            concat('"', view_table_usage.view_schema, '"') AS concat
    ) AS view_schema_reference,
    (
        SELECT
            concat('"', view_table_usage.table_schema, '"') AS concat
    ) AS table_schema_reference
FROM
    information_schema.view_table_usage
WHERE
    view_table_usage.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );

-- datahub_schema."views" source
CREATE
OR REPLACE VIEW datahub_schema."views" AS
SELECT
    views.table_catalog,
    views.table_schema,
    views.table_name,
    views.view_definition,
    views.check_option,
    views.is_updatable,
    views.is_insertable_into,
    views.is_trigger_updatable,
    views.is_trigger_deletable,
    views.is_trigger_insertable_into,
    (
        SELECT
            concat(
                '"',
                views.table_schema,
                '"."',
                views.table_name,
                '"'
            ) AS concat
    ) AS view_reference,
    (
        SELECT
            concat('"', views.table_schema, '"') AS concat
    ) AS schema_reference
FROM
    information_schema.views
WHERE
    views.table_schema :: name <> ALL (
        ARRAY ['pg_catalog'::name, 'information_schema'::name]
    );