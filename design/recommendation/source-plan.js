// UI prototype. Candidate IDs are supplied by the shared recommendation filters.
const sourcePlan = [
  { id: 'zucchini', name: 'Кабачок', group: 'vegetables' },
  { id: 'cauliflower', name: 'Цветная капуста', group: 'vegetables' },
  { id: 'broccoli', name: 'Брокколи', group: 'vegetables' },
  { id: 'buckwheat-groats', name: 'Гречневая каша', group: 'grains' },
  { id: 'iron', name: 'Источник железа', candidates: [
    { id: 'rabbit', name: 'Кролик' },
    { id: 'turkey', name: 'Индейка' },
    { id: 'beef', name: 'Говядина' }
  ], group: 'iron' },
  { id: 'rice', name: 'Рисовая каша', group: 'grains' },
  { id: 'corn-grits', name: 'Кукурузная каша', group: 'grains' }
];

function nextPlanAction({ familiar = [], eligible = [], skippedToday = [], gate, canStart = true }) {
  if (gate && gate.kind !== 'continue') return gate;
  if (!canStart) return { kind: 'needsContext' };
  if (gate) {
    if (!gate.eligibleToContinue) return { kind: 'review' };
    return gate;
  }

  const known = new Set(familiar);
  const allowed = new Set(eligible);
  const skipped = new Set(skippedToday);
  const pending = sourcePlan.filter(step => {
    const candidates = step.candidates ?? [step];
    return candidates.every(product => !known.has(product.id));
  });
  if (!pending.length) return { kind: 'complete' };

  for (const step of pending) {
    const candidates = step.candidates ?? [step];
    const product = candidates.find(item => allowed.has(item.id) && !skipped.has(item.id));
    if (product) return { kind: 'try', step: step.id, product: product.id, name: product.name };
  }
  return { kind: 'empty' };
}
