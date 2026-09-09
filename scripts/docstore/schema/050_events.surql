-- 050_events.surql
-- Automatic audit trail. Runs inside the same transaction as the write.

DEFINE EVENT OVERWRITE adr_status_change ON TABLE adr
  WHEN $event = "UPDATE" AND $before.status != $after.status THEN (
    CREATE decision_log SET
      subject = $after.id,
      actor   = ($auth.id OR "system"),
      action  = "adr_status_changed",
      from    = $before.status,
      to      = $after.status
  );

DEFINE EVENT OVERWRITE adr_created ON TABLE adr
  WHEN $event = "CREATE" THEN (
    CREATE decision_log SET
      subject = $after.id,
      actor   = ($auth.id OR "system"),
      action  = "adr_created",
      to      = $after.status
  );

DEFINE EVENT OVERWRITE todo_status_change ON TABLE todo
  WHEN $event = "UPDATE" AND $before.status != $after.status THEN (
    CREATE decision_log SET
      subject = $after.id,
      actor   = ($auth.id OR "system"),
      action  = "todo_status_changed",
      from    = $before.status,
      to      = $after.status
  );

DEFINE EVENT OVERWRITE todo_close_stamp ON TABLE todo
  WHEN $event = "UPDATE"
   AND $before.status NOT IN ["done","dropped"]
   AND $after.status IN ["done","dropped"] THEN (
    UPDATE $after.id SET closed_at = time::now()
  );

DEFINE EVENT OVERWRITE document_status_change ON TABLE document
  WHEN $event = "UPDATE" AND $before.status != $after.status THEN (
    CREATE decision_log SET
      subject = $after.id,
      actor   = ($auth.id OR "system"),
      action  = "document_status_changed",
      from    = $before.status,
      to      = $after.status,
      rationale = $after.retracted_reason
  );
