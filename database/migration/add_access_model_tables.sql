-- =====================================================================================
-- DRAFT FOR APPROVAL - NOT APPLIED. Access model, step (a) part 1: tables only.
-- Roles and privileges, customer-group data scope, active tenancy per session, tenant phone numbers.
-- Functions (fnd_has_access, fnd_scope_*, group-effective rebuild) and all RLS policies come in the next step.
-- =====================================================================================

-- ---- Customer groups (data scope, tenant users only) ----
CREATE TABLE bps.fnd_customer_groups (
  group_id         BIGINT PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  group_name       TEXT   NOT NULL,
  is_all_customers BOOLEAN NOT NULL DEFAULT false,   -- flag only: no member rows, skips the customer check
  is_active        BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT,
  UNIQUE (tenant_id, group_name)
);
CREATE UNIQUE INDEX uq_fnd_customer_groups_all ON bps.fnd_customer_groups (tenant_id) WHERE is_all_customers;

CREATE TABLE bps.fnd_customer_group_members (     -- explicit membership (never for the All Customers group)
  tenant_id   BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  group_id    BIGINT NOT NULL REFERENCES bps.fnd_customer_groups(group_id) ON DELETE CASCADE,
  customer_id BIGINT NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  PRIMARY KEY (group_id, customer_id)
);
CREATE INDEX idx_fnd_cgm_tenant_customer ON bps.fnd_customer_group_members (tenant_id, customer_id);

CREATE TABLE bps.fnd_customer_group_effective (   -- maintained by triggers: own groups, else nearest ancestor's
  tenant_id   BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id BIGINT NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  group_id    BIGINT NOT NULL REFERENCES bps.fnd_customer_groups(group_id) ON DELETE CASCADE,
  PRIMARY KEY (customer_id, group_id)
);
CREATE INDEX idx_fnd_cge_group ON bps.fnd_customer_group_effective (tenant_id, group_id, customer_id);

CREATE TABLE bps.fnd_user_customer_groups (       -- which groups a tenant user may see
  tenant_id BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  user_id   BIGINT NOT NULL REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  group_id  BIGINT NOT NULL REFERENCES bps.fnd_customer_groups(group_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  PRIMARY KEY (user_id, group_id)
);
CREATE INDEX idx_fnd_ucg_tenant_user ON bps.fnd_user_customer_groups (tenant_id, user_id);

-- ---- Roles, areas, access ----
CREATE TABLE bps.fnd_roles (
  role_id           BIGINT PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id         BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  owner_customer_id BIGINT REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE, -- NULL = tenant-level role; set = created by that customer, visible only beneath it
  role_name         TEXT NOT NULL,
  role_audience     TEXT NOT NULL CHECK (role_audience IN ('TENANT','CUSTOMER')),
  is_system         BOOLEAN NOT NULL DEFAULT false,   -- seeded (Tenant Administrator, Customer Administrator); cannot be deleted
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT,
  CHECK (owner_customer_id IS NULL OR role_audience = 'CUSTOMER')
);
CREATE UNIQUE INDEX uq_fnd_roles_name ON bps.fnd_roles (tenant_id, COALESCE(owner_customer_id, 0), role_name);

CREATE TABLE bps.fnd_user_roles (
  tenant_id BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  user_id   BIGINT NOT NULL REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  role_id   BIGINT NOT NULL REFERENCES bps.fnd_roles(role_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  PRIMARY KEY (user_id, role_id)
);
CREATE INDEX idx_fnd_user_roles_tenant_user ON bps.fnd_user_roles (tenant_id, user_id);

CREATE TABLE bps.fnd_areas (                        -- global registry of modules/areas, seeded from the menu
  area_key      TEXT PRIMARY KEY,                   -- e.g. 'production.process', 'financials.credits'
  module        TEXT NOT NULL,
  area_name     TEXT NOT NULL,
  audience      TEXT NOT NULL CHECK (audience IN ('TENANT','CUSTOMER')),
  display_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE bps.fnd_role_area_access (
  tenant_id   BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  role_id     BIGINT NOT NULL REFERENCES bps.fnd_roles(role_id) ON DELETE CASCADE,
  area_key    TEXT   NOT NULL REFERENCES bps.fnd_areas(area_key),
  can_read    BOOLEAN NOT NULL DEFAULT false,
  can_write   BOOLEAN NOT NULL DEFAULT false,
  can_approve BOOLEAN NOT NULL DEFAULT false,
  can_void    BOOLEAN NOT NULL DEFAULT false,
  can_delete  BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (role_id, area_key),
  CHECK (NOT (can_write OR can_approve OR can_void OR can_delete) OR can_read)  -- any action implies read
);

ALTER TABLE bps.fnd_tenants ADD COLUMN allow_multiple_roles BOOLEAN NOT NULL DEFAULT true;

-- ---- Active tenancy, one row per auth session (read by the token hook; never trusted from the browser) ----
CREATE TABLE bps.fnd_user_active_tenant (
  auth_session_id UUID PRIMARY KEY,                 -- the Supabase auth session
  user_id     BIGINT NOT NULL REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  tenant_id   BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  selected_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Inbound channels (voice / SMS / WhatsApp) -> tenant ----
CREATE TABLE bps.fnd_tenant_phone_numbers (
  phone_number_id BIGINT PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id    BIGINT REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,  -- NULL only for a shared fallback number
  phone_number TEXT NOT NULL,                       -- E.164
  channel      TEXT NOT NULL CHECK (channel IN ('VOICE','SMS','WHATSAPP')),
  label        TEXT,
  is_shared    BOOLEAN NOT NULL DEFAULT false,      -- shared number: tenant resolved by matching the caller to customers
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT,
  UNIQUE (phone_number, channel),
  CHECK (is_shared = (tenant_id IS NULL))
);
