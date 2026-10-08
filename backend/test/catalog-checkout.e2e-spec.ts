import { addressAt, createTestApp, login, NEAR_BOTH, PRODUCTS, TestContext } from './helpers';

describe('Search, product selection, address and 4 km check', () => {
  let ctx: TestContext;
  let token: string;

  beforeEach(async () => {
    ctx = await createTestApp();
    token = (await login(ctx, '9876543210')).accessToken;
  });
  afterEach(() => ctx.app.close());

  const search = (q: string) =>
    ctx.http().get('/api/v1/products/search').query({ q }).set('authorization', `Bearer ${token}`).expect(200);
  const checkout = (body: object) => ctx.http().post('/api/v1/checkout').set('authorization', `Bearer ${token}`).send(body);
  const oneBread = [{ productId: PRODUCTS.bread, qty: 1 }];

  describe('Product search (FR-U-03, FR-U-04)', () => {
    it('TC-U-020, TC-U-027: finds a product by full name with its price', async () => {
      const { body } = await search('Bread');
      expect(body.items).toEqual([{ id: PRODUCTS.bread, name: 'Bread', unit: '400 g', pricePaise: 4500, imageUrl: null }]);
    });

    it('TC-U-021, TC-U-022: matches part of a name and ignores case', async () => {
      const { body } = await search('mILk');
      expect(body.items.map((p: any) => p.name)).toEqual(['Milk 1L', 'Milk 500ml']);
    });

    it('lists names that start with the search first', async () => {
      const { body } = await search('ice');
      expect(body.items.map((p: any) => p.name)).toEqual(['Rice 5kg']);
    });

    it.each(['zzzz', '   ', "%' OR 1=1 --", '%', '_'])('TC-U-023 to TC-U-025: "%s" returns no products', async (q) => {
      const { body } = await search(q);
      expect(body.items).toEqual([]);
    });

    it('does not show inactive products', async () => {
      const { body } = await search('Biscuits');
      expect(body.items).toEqual([]);
    });
  });

  describe('Product selection (FR-U-05, BR-05, BR-23)', () => {
    it('TC-U-031: an order needs at least one product', async () => {
      const res = await checkout({ items: [], address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }) }).expect(400);
      expect(res.body.error.code).toBe('EMPTY_ORDER');
    });

    it('TC-U-033, TC-U-034: total is calculated on the server with no delivery charge or minimum', async () => {
      const res = await checkout({
        items: [
          { productId: PRODUCTS.milk1l, qty: 2 },
          { productId: PRODUCTS.bread, qty: 1 },
        ],
        address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }),
      }).expect(201);
      expect(res.body.totalPaise).toBe(2 * 6800 + 4500);
      expect(res.body.currency).toBe('INR');
    });

    it('rejects a price sent by the app', async () => {
      const res = await checkout({
        items: [{ productId: PRODUCTS.rice, qty: 1, pricePaise: 1 }],
        address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }),
      }).expect(400);
      expect(res.body.error.code).toBe('INVALID_INPUT');
    });

    it('limits quantity to 10 per product', async () => {
      const res = await checkout({
        items: [{ productId: PRODUCTS.bread, qty: 11 }],
        address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }),
      }).expect(400);
      expect(res.body.error.fields).toEqual(['items.0.qty']);
    });

    it('reports products that are no longer sold', async () => {
      const res = await checkout({
        items: [{ productId: PRODUCTS.discontinued, qty: 1 }],
        address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }),
      }).expect(422);
      expect(res.body.error).toMatchObject({ code: 'PRODUCT_UNAVAILABLE', productIds: [PRODUCTS.discontinued] });
    });
  });

  describe('Delivery address (FR-U-06, BR-06, BR-07)', () => {
    it('TC-U-037, TC-U-041 to TC-U-044: lists every missing field at once', async () => {
      const address = { ...addressAt(ctx, NEAR_BOTH, { STR001: 2500 }), house: '', city: '   ', pincode: undefined };
      const res = await checkout({ items: oneBread, address }).expect(400);
      expect(res.body.error.code).toBe('INVALID_ADDRESS');
      expect(res.body.error.fields.sort()).toEqual(['city', 'house', 'pincode']);
    });

    it.each(['41100', '4110381', '41A038', '011038'])('TC-U-038 to TC-U-040: pincode "%s" is rejected', async (pincode) => {
      const res = await checkout({ items: oneBread, address: { ...addressAt(ctx, NEAR_BOTH, {}), pincode } }).expect(400);
      expect(res.body.error).toMatchObject({ code: 'INVALID_ADDRESS', fields: ['pincode'] });
    });

    it('TC-U-045: the address is required', async () => {
      const res = await checkout({ items: oneBread }).expect(400);
      expect(res.body.error.fields).toContain('address');
    });

    it('uses the typed address when there is no map pin', async () => {
      const address = { ...addressAt(ctx, NEAR_BOTH, { STR001: 2500 }), lat: undefined, lng: undefined };
      ctx.maps.geocoded.set('Flat 12, Paud Road, Pune 411038, India', NEAR_BOTH);
      const res = await checkout({ items: oneBread, address }).expect(201);
      expect(res.body.roadDistanceMeters).toBe(2500);
    });

    it('asks for a map pin when the typed address cannot be found', async () => {
      const address = { ...addressAt(ctx, NEAR_BOTH, {}), lat: undefined, lng: undefined, street: 'Nowhere Lane' };
      const res = await checkout({ items: oneBread, address }).expect(422);
      expect(res.body.error.code).toBe('ADDRESS_NOT_FOUND');
    });
  });

  describe('Store within 4 km by road (FR-U-07, FR-U-08, BR-08, BR-14)', () => {
    const storeCode = async (storeId: string) =>
      (await ctx.db.query(`SELECT code FROM stores WHERE id = $1`, [storeId]))[0].code;

    it('TC-U-047, TC-U-052: picks the nearest store by road and locks it on the checkout', async () => {
      const res = await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 2500, STR002: 3800 }) }).expect(201);
      expect(await storeCode(res.body.storeId)).toBe('STR001');
      expect(res.body.roadDistanceMeters).toBe(2500);
    });

    it('chooses by road distance, not straight-line distance', async () => {
      const res = await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 3900, STR002: 1800 }) }).expect(201);
      expect(await storeCode(res.body.storeId)).toBe('STR002');
    });

    it('TC-U-048, TC-U-053: no store nearby shows the agreed message and skips the maps call', async () => {
      const res = await checkout({ items: oneBread, address: addressAt(ctx, { lat: 18.7, lng: 73.8077 }, {}) }).expect(422);
      expect(res.body.error).toEqual({ code: 'NO_STORE_AVAILABLE', message: 'Currently no store is available in your area' });
      expect(ctx.maps.calls).toBe(0);
    });

    it('TC-U-049: within 4 km straight-line but 4.6 km by road is not served', async () => {
      const res = await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 4600 }) }).expect(422);
      expect(res.body.error.code).toBe('NO_STORE_AVAILABLE');
    });

    it('TC-U-050, TC-U-051: exactly 4.0 km is served, 4.1 km is not', async () => {
      await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 4000 }) }).expect(201);
      const far = { lat: 18.516, lng: 73.8077 };
      await checkout({ items: oneBread, address: addressAt(ctx, far, { STR001: 4100, STR002: 4200 }) }).expect(422);
    });

    it('a tie goes to the lower store code', async () => {
      const res = await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 3000, STR002: 3000 }) }).expect(201);
      expect(await storeCode(res.body.storeId)).toBe('STR001');
    });

    it('a maps outage blocks payment instead of guessing', async () => {
      ctx.maps.down = true;
      const res = await checkout({ items: oneBread, address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }) }).expect(503);
      expect(res.body.error.code).toBe('SERVICEABILITY_UNAVAILABLE');
    });
  });
});
