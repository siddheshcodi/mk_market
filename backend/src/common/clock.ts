/** Injected so expiry rules can be tested without waiting. */
export abstract class Clock {
  abstract now(): Date;
}

export class SystemClock extends Clock {
  now() {
    return new Date();
  }
}

export function addSeconds(date: Date, seconds: number) {
  return new Date(date.getTime() + seconds * 1000);
}
