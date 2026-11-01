-- House-style plpgsql function — for the RARE case Rule 7 allows:
-- genuinely set-based work, or a cross-writer invariant no constraint can
-- express. Business workflows belong in a Phoenix context (Ecto.Multi).
--
-- Ship it from an Ecto migration with explicit up/down:
--   def up,   do: execute("<this whole CREATE OR REPLACE statement>")
--   def down, do: execute("DROP FUNCTION IF EXISTS recalculate_order_totals(bigint[])")
-- A later change is a NEW migration: new body in up, previous body in down.
-- Call it parameterized from the context:
--   Repo.query!("SELECT recalculate_order_totals($1)", [order_ids])
--
-- Contract is fully explicit: language, volatility, security, search_path.
-- Args validated first and rejected loudly; body is set-based, not a loop.
-- Key types are bigint to match Ecto's default id. Assumes orders.total_cents exists.

CREATE OR REPLACE FUNCTION recalculate_order_totals(
  p_order_ids bigint[]
) RETURNS integer
LANGUAGE plpgsql
VOLATILE                            -- it writes; declare it honestly
SECURITY INVOKER                    -- DEFINER only with a written reason
SET search_path = public, pg_temp   -- pin it; never trust the caller's path
AS $$
DECLARE
  v_count integer;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. validate the contract; fail specific, with a sqlstate
  --    (arrives in Elixir as %Postgrex.Error{postgres: %{code: :check_violation}})
  ---------------------------------------------------------------------------
  IF p_order_ids IS NULL OR cardinality(p_order_ids) = 0 THEN
    RAISE EXCEPTION 'recalculate_order_totals: at least one order id is required'
      USING errcode = 'check_violation';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. do the work as a SET, not a FOR ... LOOP of single-row updates
  ---------------------------------------------------------------------------
  UPDATE orders o
  SET    total_cents = s.total_cents,
         updated_at  = now()
  FROM  (SELECT order_id, sum(line_cents) AS total_cents
         FROM   order_items
         WHERE  order_id = ANY (p_order_ids)
         GROUP  BY order_id) s
  WHERE  o.id = s.order_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- The function is the front door, constraints are the walls: the CHECKs /
-- FKs / generated column in schema.sql still hold even if a backfill or a
-- psql session bypasses this function entirely.
