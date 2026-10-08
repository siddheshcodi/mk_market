import { canTransition, OrderStatus } from './order-status';
import { newDisplayOrderId } from './display-id';

describe('order status rules (FR-G-01, BR-22)', () => {
  const all: OrderStatus[] = ['PLACED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'UNDELIVERED'];
  const allowed = new Set(['PLACED>OUT_FOR_DELIVERY', 'OUT_FOR_DELIVERY>DELIVERED', 'OUT_FOR_DELIVERY>UNDELIVERED']);

  it.each(all.flatMap((from) => all.map((to) => [from, to] as const)))('%s -> %s', (from, to) => {
    expect(canTransition(from, to)).toBe(allowed.has(`${from}>${to}`));
  });
});

describe('display order ID', () => {
  it('uses the order date in IST', () => {
    // 20:00 UTC on 7 Oct is 01:30 IST on 8 Oct.
    expect(newDisplayOrderId(new Date('2026-10-07T20:00:00Z'))).toMatch(/^MK261008[A-HJ-NP-Z2-9]{6}$/);
  });
});
