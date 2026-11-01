-- Reference schema — the SQL produced by templates/migration.exs.
-- Use it to review DDL, read `\d` output in psql, or reason about the
-- database without Ecto. Author changes in the migration, not here.
-- Names are Ecto's defaults (<table>_<cols>_index, <table>_<col>_fkey) so
-- changeset constraint helpers match without `name:`; CHECKs are named.

BEGIN;

-- Rule 5: small, stable, code-driven set -> native enum, not a lookup table.
CREATE TYPE order_status AS ENUM (
  'pending', 'paid', 'shipped', 'delivered', 'cancelled'
);

-- Rule 1/2: plural table, Ecto's default `id bigserial primary key`,
-- natural key is a UNIQUE index. text, never varchar(n). timestamptz.
CREATE TABLE customers (
  id          bigserial   PRIMARY KEY,
  email       text        NOT NULL,
  full_name   text        NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_email_shape CHECK (position('@' in email) > 1)
);
CREATE UNIQUE INDEX customers_email_index ON customers (email);

CREATE TABLE products (
  id          bigserial   PRIMARY KEY,
  sku         text        NOT NULL,
  name        text        NOT NULL,
  price_cents integer     NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT products_price_cents_nonneg CHECK (price_cents >= 0)
);
CREATE UNIQUE INDEX products_sku_index ON products (sku);

CREATE TABLE coupons (
  id          bigserial   PRIMARY KEY,
  code        text        NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX coupons_code_index ON coupons (code);

CREATE TABLE orders (
  id          bigserial    PRIMARY KEY,
  -- Rule 4: FK NOT NULL by default, ON DELETE explicit (RESTRICT: never
  -- delete a customer with order history).
  customer_id bigint       NOT NULL
    CONSTRAINT orders_customer_id_fkey REFERENCES customers (id) ON DELETE RESTRICT,
  -- Rule 4 override: a nullable FK MUST carry this comment or it is a defect.
  -- nullable-fk: a coupon is genuinely optional; cleared if the coupon is deleted.
  coupon_id   bigint
    CONSTRAINT orders_coupon_id_fkey REFERENCES coupons (id) ON DELETE SET NULL,
  status      order_status NOT NULL DEFAULT 'pending',
  inserted_at timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX orders_customer_id_index ON orders (customer_id);
CREATE INDEX orders_coupon_id_index   ON orders (coupon_id);
CREATE INDEX orders_status_index      ON orders (status);

CREATE TABLE order_items (
  id          bigserial PRIMARY KEY,
  order_id    bigint  NOT NULL REFERENCES orders   (id) ON DELETE CASCADE,  -- child dies with parent
  product_id  bigint  NOT NULL REFERENCES products (id) ON DELETE RESTRICT, -- can't delete a sold product
  quantity    integer NOT NULL,
  unit_cents  integer NOT NULL,
  -- Rule 6: derived value we aggregate on -> STORED generated column,
  -- never a trigger, never changeset code; cannot drift.
  line_cents  integer GENERATED ALWAYS AS (quantity * unit_cents) STORED,
  CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
  CONSTRAINT order_items_unit_cents_nonneg CHECK (unit_cents >= 0)
);
CREATE UNIQUE INDEX order_items_order_id_product_id_index ON order_items (order_id, product_id);
CREATE INDEX order_items_product_id_index ON order_items (product_id);

CREATE TABLE groups (
  id          bigserial   PRIMARY KEY,
  name        text        NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX groups_name_index ON groups (name);

-- Rule 3: pure many-to-many -> compound primary key, NO surrogate id,
-- both sides NOT NULL FKs, CASCADE so a membership never orphans.
CREATE TABLE customers_groups (
  customer_id bigint      NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
  group_id    bigint      NOT NULL REFERENCES groups    (id) ON DELETE CASCADE,
  added_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_groups_pkey PRIMARY KEY (customer_id, group_id)  -- the pair IS the identity
);
CREATE INDEX customers_groups_group_id_index ON customers_groups (group_id);

COMMIT;
