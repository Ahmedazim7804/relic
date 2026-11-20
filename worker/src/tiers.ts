export const MB = 1024 * 1024;
export const GB = 1024 * MB;

export const TIERS = {
  free: {
    item: 100 * GB,
    storage: null,
    vault: null,
    ring: null,
    devices: null,
    shares: null,
    shareBytes: null,
  },
  pro: {
    item: 100 * GB,
    storage: null,
    vault: null,
    ring: null,
    devices: null,
    shares: null,
    shareBytes: null,
  },
  max: {
    item: 100 * GB,
    storage: null,
    vault: null,
    ring: null,
    devices: null,
    shares: null,
    shareBytes: null,
  },
} as const;

export type Tier = keyof typeof TIERS;

export const RING_NEW_FROM = 1792454400;
export const RING_NEW = 100;

export function ringCap(_tier: Tier, _createdAt?: number | null): number | null {
  return null;
}

export async function accountCreatedAt(_db: D1Database, _account: string): Promise<number | null> {
  return null;
}

export const isTier = (s: unknown): s is Tier =>
  s === "free" || s === "pro" || s === "max";
