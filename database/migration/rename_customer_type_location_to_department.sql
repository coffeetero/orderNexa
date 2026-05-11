-- ============================================================
-- Rename customer_type LOCATION to DEPARTMENT.
--
-- Runtime functions keep accepting LOCATION as a legacy alias, but
-- persisted customer rows should use DEPARTMENT going forward.
-- ============================================================

SET search_path = bps, public;

UPDATE fnd_customers
   SET customer_type = 'DEPARTMENT'
 WHERE UPPER(TRIM(customer_type)) = 'LOCATION';

COMMENT ON COLUMN fnd_customers.customer_type IS
    'Hierarchy role (text): ACCOUNT - bill-to / top-level; SITE - invoiced under an account; DEPARTMENT - department/event grouping, not invoiced directly.';
