-- Indexes on the legacy staging tables that the seeds and reconciliation checks look up by. dataPump.py recreates these tables
-- bare on every load, so seed_all.py runs this first. Safe to rerun.
SET search_path = bps, public;
CREATE INDEX IF NOT EXISTS ix_legacy_ar_trn_id    ON bps.ar (ar_trn_id);
CREATE INDEX IF NOT EXISTS ix_legacy_ar_trn_ref   ON bps.ar (ar_trn_ref);
CREATE INDEX IF NOT EXISTS ix_legacy_ar_cus_id    ON bps.ar (cus_id);
CREATE INDEX IF NOT EXISTS ix_legacy_pmt_detail_ar  ON bps.pmt_detail (pd_ar_trn_id);
CREATE INDEX IF NOT EXISTS ix_legacy_pmt_detail_pmt ON bps.pmt_detail (pd_pmt_no);
CREATE INDEX IF NOT EXISTS ix_legacy_ordr_no      ON bps.ordr (ordr_no);
CREATE INDEX IF NOT EXISTS ix_legacy_ordr_invc_no ON bps.ordr (invc_no);
CREATE INDEX IF NOT EXISTS ix_legacy_ordr_detail_no ON bps.ordr_detail (ordr_no);
ANALYZE bps.ar; ANALYZE bps.pmt_detail; ANALYZE bps.ordr; ANALYZE bps.ordr_detail;
