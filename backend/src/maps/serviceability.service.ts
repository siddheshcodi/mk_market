import { Injectable } from '@nestjs/common';
import { Errors } from '../common/errors';
import { SERVICE_RADIUS_M } from '../common/rules';
import { Db } from '../database/db';
import { LatLng, straightLineMeters } from './geo';
import { MapsProvider, MapsUnavailableError } from './maps-provider';

export interface NearestStore {
  storeId: string;
  storeCode: string;
  roadDistanceMeters: number;
}

interface StoreRow {
  id: string;
  code: string;
  lat: number;
  lng: number;
}

@Injectable()
export class ServiceabilityService {
  constructor(
    private readonly db: Db,
    private readonly maps: MapsProvider,
  ) {}

  /** Uses the map pin when given, otherwise geocodes the typed address. */
  async locate(addressText: string, pin?: LatLng): Promise<LatLng> {
    if (pin) return pin;
    try {
      const found = await this.maps.geocode(addressText);
      if (!found) throw Errors.addressNotFound();
      return found;
    } catch (err) {
      if (err instanceof MapsUnavailableError) throw Errors.serviceabilityUnavailable();
      throw err;
    }
  }

  /**
   * FR-U-07, FR-U-08, BR-08, BR-14: the nearest active store by road, at most 4 km away.
   * Stores more than 4 km away in a straight line can't be within 4 km by road, so they are skipped
   * before calling the (paid) road-distance API.
   */
  async nearestStore(point: LatLng): Promise<NearestStore> {
    const stores = await this.db.query<StoreRow>(`SELECT id, code, lat, lng FROM stores WHERE is_active`);
    const candidates = stores.filter((s) => straightLineMeters(s, point) <= SERVICE_RADIUS_M);
    if (!candidates.length) throw Errors.noStoreAvailable();

    let distances: (number | null)[];
    try {
      distances = await this.maps.roadDistancesMeters(candidates, point);
    } catch (err) {
      // Never treat a maps failure as "serviceable".
      if (err instanceof MapsUnavailableError) throw Errors.serviceabilityUnavailable();
      throw err;
    }

    const inRange = candidates
      .map((store, i) => ({ store, meters: distances[i] }))
      .filter((c): c is { store: StoreRow; meters: number } => c.meters !== null && c.meters <= SERVICE_RADIUS_M)
      // Ties go to the lower store code so the result is always the same.
      .sort((a, b) => a.meters - b.meters || a.store.code.localeCompare(b.store.code));
    if (!inRange.length) throw Errors.noStoreAvailable();

    const best = inRange[0];
    return { storeId: best.store.id, storeCode: best.store.code, roadDistanceMeters: best.meters };
  }
}
