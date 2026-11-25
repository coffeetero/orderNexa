import { Fragment } from 'react';

/** A label as built by the database (inv_nutrition_label_build): amounts are already rounded and % Daily Values worked out. */
export interface LabelRow { code: string; label: string; indent: number; amounts: string[]; dv: (number | null)[] }
export interface NutritionLabelData {
  label_format: 'STANDARD' | 'TABULAR' | 'LINEAR';
  is_dual_column: boolean;
  columns: string[] | null;
  servings_text: string | null;
  serving_size_text: string | null;
  calories: string[];
  nutrients: LabelRow[];
  vitamins: LabelRow[];
  footnote: string;
  ingredient_statement: string | null;
  contains_statement: string | null;
  may_contain_text: string | null;
  issues: string[];
}

// Black on white whatever the app theme; Helvetica as FDA uses.
const FONT = { fontFamily: '"Helvetica Neue", Helvetica, Arial, sans-serif', color: '#000', background: '#fff' } as const;
const pct = (v: number | null | undefined) => (v === null || v === undefined ? '' : `${v}%`);

function RowName({ r, amount }: { r: LabelRow; amount?: string }) {
  if (r.code === 'added_sugars') return <span>Includes {amount ?? ''} Added Sugars</span>;
  const name = r.code === 'trans_fat' ? <><i>Trans</i> Fat</> : r.label;
  return (
    <span>
      {r.indent === 0 ? <b>{name}</b> : name}
      {amount !== undefined && <> {amount}</>}
    </span>
  );
}

function Bar({ h }: { h: number }) {
  return <div style={{ height: h, background: '#000' }} />;
}

function Standard({ l }: { l: NutritionLabelData }) {
  // FDA: the rule above "Includes … Added Sugars" starts at its indent; other rules run the full width.
  const rowStyle = (r: LabelRow) => (r.code === 'added_sugars'
    ? { borderTop: '1px solid #000', marginLeft: r.indent * 12 }
    : { borderTop: '1px solid #000', paddingLeft: r.indent * 12 });
  return (
    <div style={{ ...FONT, width: 264, border: '1px solid #000', padding: '4px 6px', fontSize: 12, lineHeight: 1.25 }}>
      <div style={{ fontSize: 33, fontWeight: 900, lineHeight: 1, letterSpacing: -0.5, margin: '0 0 2px' }}>Nutrition Facts</div>
      <div style={{ borderTop: '1px solid #000', paddingTop: 2, fontSize: 14 }}>{l.servings_text ?? ' '}</div>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 15, fontWeight: 800, gap: 8 }}>
        <span>Serving size</span><span style={{ textAlign: 'right' }}>{l.serving_size_text ?? ''}</span>
      </div>
      <Bar h={10} />
      <div style={{ fontSize: 11, fontWeight: 800, paddingTop: 2 }}>Amount per serving</div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', fontWeight: 900, lineHeight: 1 }}>
        <span style={{ fontSize: 28 }}>Calories</span><span style={{ fontSize: 36 }}>{l.calories[0] ?? ''}</span>
      </div>
      <Bar h={5} />
      <div style={{ textAlign: 'right', fontSize: 11, fontWeight: 800, padding: '1px 0' }}>% Daily Value*</div>
      {l.nutrients.map((r) => (
        <div key={r.code} style={{ ...rowStyle(r), display: 'flex', justifyContent: 'space-between', gap: 6 }}>
          <RowName r={r} amount={r.amounts[0]} />
          <b>{pct(r.dv[0])}</b>
        </div>
      ))}
      <Bar h={10} />
      {l.vitamins.map((r, i) => (
        <div key={r.code} style={{ borderTop: i === 0 ? 'none' : '1px solid #000', display: 'flex', justifyContent: 'space-between', gap: 6 }}>
          <span>{r.label} {r.amounts[0]}</span><span>{pct(r.dv[0])}</span>
        </div>
      ))}
      <Bar h={5} />
      <Footnote text={l.footnote} />
    </div>
  );
}

function Footnote({ text }: { text: string }) {
  return (
    <div style={{ display: 'flex', gap: 2, fontSize: 9, lineHeight: 1.2, paddingTop: 3 }}>
      <span>*</span><span>{text}</span>
    </div>
  );
}

function Dual({ l }: { l: NutritionLabelData }) {
  const cols = l.columns ?? [];
  const sep = { borderLeft: '1px solid #000', paddingLeft: 4 } as const;
  const line = { borderTop: '1px solid #000' } as const;
  return (
    <div style={{ ...FONT, width: 380, border: '1px solid #000', padding: '4px 6px', fontSize: 12, lineHeight: 1.25 }}>
      <div style={{ fontSize: 33, fontWeight: 900, lineHeight: 1, letterSpacing: -0.5, margin: '0 0 2px' }}>Nutrition Facts</div>
      <div style={{ borderTop: '1px solid #000', paddingTop: 2, fontSize: 14 }}>{l.servings_text ?? ' '}</div>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 15, fontWeight: 800, gap: 8 }}>
        <span>Serving size</span><span style={{ textAlign: 'right' }}>{l.serving_size_text ?? ''}</span>
      </div>
      <Bar h={10} />
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <colgroup><col /><col style={{ width: 52 }} /><col style={{ width: 36 }} /><col style={{ width: 52 }} /><col style={{ width: 36 }} /></colgroup>
        <tbody>
          <tr style={{ fontSize: 11, fontWeight: 800 }}>
            <td />
            {cols.map((c) => <td key={c} colSpan={2} style={{ ...sep, paddingTop: 2 }}>{c}</td>)}
          </tr>
          <tr style={{ fontWeight: 900, lineHeight: 1 }}>
            <td style={{ fontSize: 24, verticalAlign: 'bottom' }}>Calories</td>
            {l.calories.map((c, i) => <td key={i} colSpan={2} style={{ ...sep, fontSize: 30, textAlign: 'right', paddingRight: 2 }}>{c}</td>)}
          </tr>
          <tr><td colSpan={5} style={{ padding: 0 }}><Bar h={5} /></td></tr>
          <tr style={{ fontSize: 10, fontWeight: 800 }}>
            <td />
            {cols.map((c) => <Fragment key={c}><td style={sep} /><td style={{ textAlign: 'right' }}>% DV*</td></Fragment>)}
          </tr>
          {l.nutrients.map((r) => (
            <tr key={r.code} style={line}>
              <td style={{ paddingLeft: r.indent * 10 }}>{r.code === 'added_sugars' ? 'Incl. Added Sugars' : <RowName r={r} />}</td>
              {r.amounts.map((a, i) => (
                <Fragment key={i}><td style={sep}>{a}</td><td style={{ textAlign: 'right', fontWeight: 800 }}>{pct(r.dv[i])}</td></Fragment>
              ))}
            </tr>
          ))}
          <tr><td colSpan={5} style={{ padding: 0 }}><Bar h={10} /></td></tr>
          {l.vitamins.map((r, idx) => (
            <tr key={r.code} style={idx === 0 ? undefined : line}>
              <td>{r.label}</td>
              {r.amounts.map((a, i) => <Fragment key={i}><td style={sep}>{a}</td><td style={{ textAlign: 'right' }}>{pct(r.dv[i])}</td></Fragment>)}
            </tr>
          ))}
        </tbody>
      </table>
      <Bar h={5} />
      <Footnote text={l.footnote} />
    </div>
  );
}

function Tabular({ l }: { l: NutritionLabelData }) {
  const half = Math.ceil(l.nutrients.length / 2);
  const halves = [l.nutrients.slice(0, half), l.nutrients.slice(half)];
  return (
    <div style={{ ...FONT, display: 'flex', border: '1px solid #000', padding: 4, fontSize: 11, lineHeight: 1.25, width: 620 }}>
      <div style={{ width: 150, paddingRight: 6, borderRight: '1px solid #000' }}>
        <div style={{ fontSize: 26, fontWeight: 900, lineHeight: 1, letterSpacing: -0.5 }}>Nutrition Facts</div>
        <div style={{ borderTop: '1px solid #000', marginTop: 2 }}>{l.servings_text}</div>
        <div style={{ fontWeight: 800 }}>Serving size</div>
        <div style={{ fontWeight: 800 }}>{l.serving_size_text}</div>
        <Bar h={6} />
        <div style={{ fontWeight: 800, fontSize: 10 }}>Amount per serving</div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', fontWeight: 900, lineHeight: 1 }}>
          <span style={{ fontSize: 20 }}>Calories</span><span style={{ fontSize: 26 }}>{l.calories[0]}</span>
        </div>
      </div>
      <div style={{ flex: 1, paddingLeft: 6 }}>
        <div style={{ display: 'flex', gap: 10 }}>
          {halves.map((rows, h) => (
            <div key={h} style={{ flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, fontWeight: 800, borderBottom: '4px solid #000' }}>
                <span>Amount/serving</span><span>% Daily Value*</span>
              </div>
              {rows.map((r, i) => (
                <div key={r.code} style={{ display: 'flex', justifyContent: 'space-between', gap: 4, borderTop: i === 0 ? 'none' : '1px solid #000', paddingLeft: r.indent * 8 }}>
                  <RowName r={r} amount={r.amounts[0]} /><b>{pct(r.dv[0])}</b>
                </div>
              ))}
            </div>
          ))}
        </div>
        <div style={{ borderTop: '6px solid #000', paddingTop: 2 }}>
          {l.vitamins.map((r) => `${r.label} ${r.amounts[0]} ${pct(r.dv[0])}`).join(' • ')}
        </div>
        <Footnote text={l.footnote} />
      </div>
    </div>
  );
}

const LINEAR_NAMES: Record<string, string> = {
  total_fat: 'Total Fat', saturated_fat: 'Sat. Fat', polyunsaturated_fat: 'Polyunsat. Fat', monounsaturated_fat: 'Monounsat. Fat',
  cholesterol: 'Cholest.', total_carbohydrate: 'Total Carb.', dietary_fiber: 'Fiber', soluble_fiber: 'Sol. Fiber',
  insoluble_fiber: 'Insol. Fiber', sugar_alcohol: 'Sugar Alc.', potassium: 'Potas.', vitamin_d: 'Vit. D', vitamin_a: 'Vit. A', vitamin_c: 'Vit. C',
};

function Linear({ l }: { l: NutritionLabelData }) {
  const part = (r: LabelRow) => {
    const dv = r.dv[0] === null ? '' : ` (${r.dv[0]}% DV)`;
    if (r.code === 'added_sugars') return <>Incl. {r.amounts[0]} Added Sugars{dv}</>;
    if (r.code === 'trans_fat') return <><i>Trans</i> Fat {r.amounts[0]}</>;
    const name = LINEAR_NAMES[r.code] ?? r.label;
    return <>{r.indent === 0 && !r.code.startsWith('vitamin') && !['calcium', 'iron', 'potassium'].includes(r.code) ? <b>{name}</b> : name} {r.amounts[0]}{dv}</>;
  };
  const rows = [...l.nutrients, ...l.vitamins];
  return (
    <p style={{ ...FONT, border: '1px solid #000', padding: '3px 5px', fontSize: 10, lineHeight: 1.3, maxWidth: 520, margin: 0 }}>
      <b style={{ fontSize: 12, fontWeight: 900 }}>Nutrition Facts</b>{' '}
      {l.servings_text && <>Servings: {l.servings_text.replace(/ servings? per container$/, '')}, </>}
      <b>Serv. size:</b> {l.serving_size_text}, <b>Amount per serving: Calories</b> {l.calories[0]}
      {rows.map((r) => <Fragment key={r.code}>, {part(r)}</Fragment>)}.
    </p>
  );
}

/** Ingredient statement, Contains statement and the voluntary advisory, printed under the panel. */
function Ingredients({ l, width }: { l: NutritionLabelData; width: number }) {
  if (!l.ingredient_statement && !l.contains_statement && !l.may_contain_text) return null;
  return (
    <div style={{ ...FONT, width, fontSize: 10, lineHeight: 1.3, marginTop: 6 }}>
      {l.ingredient_statement && <p style={{ margin: 0 }}><b>INGREDIENTS:</b> {l.ingredient_statement}</p>}
      {l.contains_statement && <p style={{ margin: '3px 0 0', fontWeight: 800 }}>{l.contains_statement.toUpperCase()}</p>}
      {l.may_contain_text && <p style={{ margin: '3px 0 0' }}>{l.may_contain_text}</p>}
    </div>
  );
}

export function NutritionFactsLabel({ label, showIngredients = true }: { label: NutritionLabelData; showIngredients?: boolean }) {
  const width = label.label_format === 'TABULAR' ? 620 : label.label_format === 'LINEAR' ? 520 : label.is_dual_column ? 380 : 264;
  return (
    <div style={{ background: '#fff', display: 'inline-block' }}>
      {label.label_format === 'LINEAR' ? <Linear l={label} /> : label.label_format === 'TABULAR' ? <Tabular l={label} /> : label.is_dual_column ? <Dual l={label} /> : <Standard l={label} />}
      {showIngredients && <Ingredients l={label} width={width} />}
    </div>
  );
}
