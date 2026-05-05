# BPS — Technical & Strategic Summary

## 1. Schema Architecture

### Prefix Convention
| Prefix | Module | Owns |
|---|---|---|
| `fnd_` | Foundation | Master/shared data |
| `om_` | Order Management | Order transactions & logic |
| `ar_` | Accounts Receivable | Invoicing, payments |

### Foundation Tables (shared master data)
```sql
fnd_customers
fnd_vendors
fnd_vendor_sites          -- includes email for invoice matching
fnd_items                 -- product catalog
fnd_pricebooks
fnd_pricebook_items       -- item + price + pricebook intersection
fnd_customer_pricebooks   -- customer → pricebook assignment
fnd_organizations         -- vendor/customer hierarchy
```

### Order Management Tables
```sql
om_orders                 -- header (lean, no delivery_charge column)
om_order_lines            -- lines including special types
  line_type: 'ITEM' | 'DELIVERY' | 'DISCOUNT' | 'TAX'
```

### Function Naming Convention
```
{prefix}_{entity}_{verb}
om_items_get(p_tenant_id bigint, p_customer_id bigint DEFAULT NULL, ...)
om_orders_get(...)
om_orders_save(...)       -- upsert pattern
om_order_lines_get(...)
om_order_lines_save(...)
```

### Overloading Strategy
PostgreSQL resolves overloads by **type signature only** — parameter names ignored.  
Solution: single function with defaulted parameters:
```sql
om_items_get(
    p_tenant_id     bigint,
    p_customer_id   bigint  DEFAULT NULL,
    p_item_id       bigint  DEFAULT NULL,
    p_category_id   bigint  DEFAULT NULL,
    p_pricebook_id  bigint  DEFAULT NULL,
    p_search_text   text    DEFAULT NULL
)
```
Call with named notation:
```sql
om_items_get(p_tenant_id => 1, p_customer_id => 42)
om_items_get(p_tenant_id => 1, p_search_text => 'widget')
```

### Multi-Tenancy
`p_tenant_id` on every function and table = true multi-tenancy.  
Shared schema, complete data isolation — superior to Odoo/SAP/Oracle approaches.

---

## 2. Useful SQL Reference

### Find function parameters
```sql
SELECT r.routine_name, p.parameter_name, p.data_type, p.ordinal_position
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE r.routine_name ILIKE '%function_name%'
AND r.routine_schema = 'bps'
ORDER BY p.ordinal_position;
```

### Rename function (must include full signature)
```sql
ALTER FUNCTION bps.om_get_items_for_order(bigint, bigint) RENAME TO om_items_get;
```

### Find references to a function (PostgreSQL)
```sql
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_definition ILIKE '%old_function_name%';
```

### Oracle equivalent
```sql
SELECT name, type, line, text
FROM all_source
WHERE UPPER(text) LIKE UPPER('%function_name%')
ORDER BY name, line;
```

---

## 3. Planned Features

### Phase 1 — In Progress
- Twilio WebRTC browser calling via Bolt.new + Pica integration
- Agent uses computer + headset, calls show company main line as caller ID
- Cost: ~$0.018/min ($0.014 outbound + $0.004 WebRTC)

### Phase 2 — 2 Weeks
- Click-to-call UI in agent dashboard
- Bolt.new prompt: *"Add call button using Twilio Voice JS SDK, caller ID = main number"*
- Requires backend token generation (Supabase Edge Function)

### Phase 3 — Weekend Project
#### IDR (Intelligent Document Recognition)
```javascript
// Send invoice image to Claude, get structured JSONB back
const response = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  body: JSON.stringify({
    model: "claude-sonnet-4-20250514",
    messages: [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: "image/jpeg", data: invoiceBase64 }},
        { type: "text", text: `Return ONLY valid JSON:
          { "vendor_name": "", "invoice_number": "", "invoice_date": "",
            "due_date": "", "line_items": [{"description":"","quantity":0,"unit_price":0,"total":0}],
            "subtotal": 0, "tax": 0, "total": 0 }` }
      ]
    }]
  })
});
```

```sql
CREATE TABLE ar_idr_documents (
    id              bigint PRIMARY KEY,
    tenant_id       bigint NOT NULL,
    document_type   text,         -- 'INVOICE','PO','RECEIPT'
    raw_image_url   text,
    extracted_data  jsonb,
    status          text,         -- 'EXTRACTED','VALIDATED','POSTED'
    confidence      numeric,
    created_at      timestamptz
);
```

---

## 4. SaaS Product Opportunity — AP Automation for Oracle Fusion

### The Problem
- Oracle Fusion IDR = rules-based, expensive, brittle
- Requires Oracle consultants at $300/hr to maintain
- Fusion contracts: $500K–$2M+/year
- Customers still manually key invoices

### The Solution
```
Vendor emails invoice → your mail server
         ↓
Claude Vision API extracts data → JSONB
         ↓
Auto-match vendor by FROM email (fnd_vendor_sites.email)
         ↓
Human review UI (exceptions only)
         ↓
Dump to Fusion AP interface tables:
  AP_INVOICES_INTERFACE
  AP_INVOICE_LINES_INTERFACE
         ↓
Fusion import runs → invoice posted ✅
```

### Fusion REST API Import
```
GET /fscmRestApi/resources/11.13.18.05/suppliers
→ populate fnd_vendors + fnd_vendor_sites automatically
→ store fusion_supplier_id for ongoing sync
```

### Vendor Schema
```sql
fnd_vendors:
    fusion_supplier_id   bigint,
    last_synced_at       timestamptz,
    sync_status          text   -- 'SYNCED','PENDING','ERROR'

fnd_vendor_sites:
    email                text   -- invoices auto-matched by FROM address
    fusion_site_id       bigint
```

### Pricing Model
| Tier | Price | Volume |
|---|---|---|
| Starter | $299/month | 500 invoices |
| Growth | $799/month | 2,000 invoices |
| Enterprise | $1,999/month | Unlimited |

**Cost to run:** Claude API ~$100/month handles thousands of invoices.

### Go-To-Market
- **YouTube channel** targeting "Oracle Fusion IDR not working" searches
- Fusion support background = instant credibility
- Target new Fusion customers (no migration pain)
- SI/Oracle partner reseller channel ($1K/month to you, $2K billed to customer)

### Design Partner Strategy
- 1 customer, lifetime $99/month
- In exchange: Fusion sandbox access + feedback calls + case study
- Source: former Oracle support network / OATUG / LinkedIn

### Competitive Moat
- Vendor email → your server = switching cost
- No rules to maintain (Claude handles any format)
- Fusion REST API import = 10-minute onboarding vs 2-day CSV process
- Built by someone who knows Fusion's limitations intimately

---

## 5. Architecture Advantages vs Legacy ERPs

| | BPS | Odoo/SAP/Oracle |
|---|---|---|
| Multi-tenancy | ✅ Native (`tenant_id`) | ❌ Separate DB per customer |
| Cloud native | ✅ | ❌ Retrofitted |
| AI features | ✅ API calls ~$100/mo | ❌ Millions to build |
| Schema control | ✅ Full | ❌ ORM-locked |
| Migration burden | ✅ None (greenfield) | ❌ Trapped by customers |

Legacy ERPs use ORM → schema changes are automatic but prevent true multi-tenancy.  
They're trapped: can't rewrite, can't migrate thousands of customers.  
**Target their new customers — zero migration friction.**