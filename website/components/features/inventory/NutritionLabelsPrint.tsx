'use client';

import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { Printer } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { adminCall } from '@/components/features/admin/adminShared';
import { NutritionFactsLabel, type NutritionLabelData } from '@/components/features/inventory/NutritionFactsLabel';

interface PrintLabel { item_id: number; item_number: string; item_name: string; status: 'DRAFT' | 'APPROVED'; label: NutritionLabelData }

// When printing, only the labels (moved to the end of <body>) are shown; the app shell is hidden.
const PRINT_CSS = `
@media print {
  @page { margin: 0.4in; }
  body > *:not(#nutrition-print) { display: none !important; }
  #nutrition-print { display: block !important; }
  html, body { background: #fff !important; height: auto !important; overflow: visible !important; }
}
#nutrition-print { display: none; }
`;

/** Printable sheet of nutrition labels: one per item, each kept on one page; browser Print or Save as PDF. */
export function NutritionLabelsPrint({ tenantId, itemIds }: { tenantId: number; itemIds: string[] }) {
  const [labels, setLabels] = useState<PrintLabel[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [names, setNames] = useState(true);
  const [mounted, setMounted] = useState(false);

  const idList = itemIds.join(',');
  useEffect(() => {
    setMounted(true);
    if (!idList) { setError('No items selected. Pick items on Nutrition Labels and choose Print.'); return; }
    adminCall<PrintLabel[]>(`/api/inventory/nutrition/labels?tenant_id=${tenantId}&item_ids=${idList}`)
      .then(setLabels)
      .catch((e: Error) => setError(e.message));
  }, [tenantId, idList]);

  const drafts = labels?.filter((l) => l.status !== 'APPROVED').length ?? 0;
  const sheet = (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 24, alignItems: 'flex-start', background: '#fff', color: '#000' }}>
      {labels?.map((l) => (
        <div key={l.item_id} style={{ breakInside: 'avoid', pageBreakInside: 'avoid' }}>
          {(names || l.status !== 'APPROVED') && (
            <div style={{ fontFamily: 'Helvetica, Arial, sans-serif', fontSize: 10, marginBottom: 3 }}>
              {names && <>{l.item_number} {l.item_name}</>}
              {l.status !== 'APPROVED' && <b style={{ marginLeft: 6 }}>DRAFT – NOT APPROVED</b>}
            </div>
          )}
          <NutritionFactsLabel label={l.label} />
        </div>
      ))}
    </div>
  );

  return (
    <div className="mx-auto max-w-[1440px] space-y-4 p-2 sm:p-3">
      <style>{PRINT_CSS}</style>
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="mr-auto text-2xl font-semibold">Print Nutrition Labels</h1>
        <label className="flex items-center gap-2 text-sm"><Checkbox checked={names} onCheckedChange={(v) => setNames(v === true)} />Show item names</label>
        <Button className="gap-1" disabled={!labels?.length} onClick={() => window.print()}><Printer className="h-4 w-4" />Print</Button>
      </div>
      <p className="text-sm text-muted-foreground">
        {labels ? `${labels.length} label${labels.length === 1 ? '' : 's'}.` : 'Loading…'} Use Print, then Save as PDF for a PDF.
        {drafts > 0 && ` ${drafts} not approved: printed with a DRAFT mark.`}
      </p>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {labels && labels.length === 0 && <p className="text-sm text-muted-foreground">None of the selected items has a label.</p>}
      <div className="rounded border bg-white p-4">{sheet}</div>
      {mounted && createPortal(<div id="nutrition-print">{sheet}</div>, document.body)}
    </div>
  );
}
