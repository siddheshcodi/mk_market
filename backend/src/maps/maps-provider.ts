import { LatLng, straightLineMeters } from './geo';

export class MapsUnavailableError extends Error {}

export abstract class MapsProvider {
  /** Returns null when the address can't be found. Throws MapsUnavailableError when the service fails. */
  abstract geocode(address: string): Promise<LatLng | null>;

  /** Driving distance in metres from each origin to the destination; null where no route exists. */
  abstract roadDistancesMeters(origins: LatLng[], destination: LatLng): Promise<(number | null)[]>;
}

/** Google Geocoding + Distance Matrix (driving), as required by BR-08 / D2. */
export class GoogleMapsProvider extends MapsProvider {
  constructor(private readonly apiKey: string) {
    super();
  }

  async geocode(address: string): Promise<LatLng | null> {
    const body = await this.get('https://maps.googleapis.com/maps/api/geocode/json', {
      address,
      region: 'in',
      components: 'country:IN',
    });
    if (body.status === 'ZERO_RESULTS') return null;
    if (body.status !== 'OK') throw new MapsUnavailableError(`Geocoding failed: ${body.status}`);
    return body.results[0].geometry.location;
  }

  async roadDistancesMeters(origins: LatLng[], destination: LatLng): Promise<(number | null)[]> {
    if (!origins.length) return [];
    const point = (p: LatLng) => `${p.lat},${p.lng}`;
    const body = await this.get('https://maps.googleapis.com/maps/api/distancematrix/json', {
      origins: origins.map(point).join('|'),
      destinations: point(destination),
      mode: 'driving',
      units: 'metric',
    });
    if (body.status !== 'OK') throw new MapsUnavailableError(`Distance Matrix failed: ${body.status}`);
    return body.rows.map((row: any) => (row.elements[0]?.status === 'OK' ? row.elements[0].distance.value : null));
  }

  private async get(url: string, params: Record<string, string>) {
    const query = new URLSearchParams({ ...params, key: this.apiKey });
    try {
      const res = await fetch(`${url}?${query}`, { signal: AbortSignal.timeout(5_000) });
      if (!res.ok) throw new MapsUnavailableError(`Maps HTTP ${res.status}`);
      return (await res.json()) as any;
    } catch (err) {
      throw err instanceof MapsUnavailableError ? err : new MapsUnavailableError(String(err));
    }
  }
}

/**
 * Development only (refused in production by loadConfig): no geocoding, so the app must send a map pin,
 * and road distance is estimated as straight-line x 1.3.
 */
export class DevMapsProvider extends MapsProvider {
  async geocode(): Promise<LatLng | null> {
    return null;
  }

  async roadDistancesMeters(origins: LatLng[], destination: LatLng) {
    return origins.map((o) => Math.round(straightLineMeters(o, destination) * 1.3));
  }
}
