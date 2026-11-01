-- The hybrid document pattern (Rule 8): relational spine + jsonb body.
-- SQL reference; the Ecto migration, schema, and query idioms that produce
-- and use this live in jsonb-document.exs. Always jsonb, never json.

BEGIN;

CREATE TABLE products (
  -- ---- relational spine: identity, relationships, integrity ----
  id          bigserial   PRIMARY KEY,
  sku         text        NOT NULL,
  category_id bigint      NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,

  -- ---- open-ended body: varies wildly per category ----
  -- NOT NULL + default '{}' so callers never branch on nil vs %{}.
  attributes  jsonb       NOT NULL DEFAULT '{}',

  -- ---- hot fields promoted OUT of the document ----
  -- Filtered/sorted -> first-class indexed columns; the document stays the
  -- source of truth. (See references/generated-columns.md.)
  price_cents integer GENERATED ALWAYS AS ((attributes->>'price_cents')::integer) STORED,
  brand       text    GENERATED ALWAYS AS (attributes->>'brand') STORED,

  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  -- A document is not an excuse to abandon validation.
  CONSTRAINT products_attributes_object CHECK (jsonb_typeof(attributes) = 'object'),
  CONSTRAINT products_price_present     CHECK (attributes ? 'price_cents'),
  CONSTRAINT products_price_nonneg      CHECK ((attributes->>'price_cents')::integer >= 0)
);

CREATE UNIQUE INDEX products_sku_index ON products (sku);
CREATE INDEX products_category_id_index ON products (category_id);
-- Containment (@>) rides this index. jsonb_path_ops: smaller/faster when you
-- only need @>. Use default jsonb_ops if you also index ? / ?| / ?&.
CREATE INDEX products_attributes_index  ON products USING gin (attributes jsonb_path_ops);
CREATE INDEX products_price_cents_index ON products (price_cents);
CREATE INDEX products_brand_index       ON products (brand);

COMMIT;

-- ---------------------------------------------------------------------------
-- Query idioms (Ecto versions in jsonb-document.exs)
-- ---------------------------------------------------------------------------
-- containment, uses the GIN index:
-- SELECT * FROM products WHERE attributes @> '{"brand":"Acme","waterproof":true}';
-- JSONPath:
-- SELECT * FROM products WHERE attributes @? '$.dimensions.width_mm ? (@ > 100)';
-- range / order: the generated column, never the raw path:
-- SELECT * FROM products WHERE price_cents BETWEEN 1000 AND 5000 ORDER BY price_cents;

-- ---------------------------------------------------------------------------
-- Mutation idioms — build the document, never overwrite the whole blob
-- ---------------------------------------------------------------------------
-- UPDATE products SET attributes = jsonb_set(attributes, '{brand}', '"Acme"', true) WHERE id = $1;
-- UPDATE products SET attributes = attributes || '{"waterproof":true}' WHERE id = $1;  -- shallow merge
-- UPDATE products SET attributes = attributes - 'discontinued_note' WHERE id = $1;
-- UPDATE products SET attributes = attributes #- '{dimensions,depth_mm}' WHERE id = $1;
