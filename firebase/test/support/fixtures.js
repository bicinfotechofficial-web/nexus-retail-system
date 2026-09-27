// Fixture data for the rules tests: roles, users and locations.
//
// Roles are read from packages/core/lib/src/permissions.dart (Permission and
// SeedRoles), so the rules suite always tests the same permission sets the
// apps and the seed script use. If that file changes shape, parsing fails
// loudly instead of drifting.

import { hashPin, parsePermissionsDart, readPermissions } from '../../scripts/lib/core.js';

export { hashPin, parsePermissionsDart };

export const PERMS = readPermissions();

export const ROLE = {
  ADMIN: PERMS.adminId,
  STORE_MANAGER: PERMS.storeManagerId,
  // Test-only roles that hold part of the permissions, so each rule can be
  // shown to need its own permission (QA-034, D-017).
  CASHIER: 'CASHIER',
  STOCK_COUNTER: 'STOCK_COUNTER',
};

/** Checks a hand-written permission list against packages/core. */
function known(permissions) {
  for (const p of permissions) {
    if (!PERMS.all.includes(p)) throw new Error(`fixtures: unknown permission ${p}`);
  }
  return permissions;
}

/** roles/{roleId} */
export const ROLES = {
  [ROLE.ADMIN]: {
    name: 'Admin',
    permissions: PERMS.adminPermissions,
    allLocations: true,
  },
  [ROLE.STORE_MANAGER]: {
    name: 'Store Manager',
    permissions: PERMS.storeManagerPermissions,
    allLocations: false,
  },
  // The CASHIER (future) column of the 04-PERMISSIONS role matrix.
  [ROLE.CASHIER]: {
    name: 'Cashier',
    permissions: known(['catalog.view', 'bill.create', 'device.register']),
    allLocations: false,
  },
  // Counts stock but can't move it: stock.adjust without stock.move (QA-029).
  [ROLE.STOCK_COUNTER]: {
    name: 'Stock Counter',
    permissions: known(['catalog.view', 'stock.adjust']),
    allLocations: false,
  },
};

export const LOC = { PTB: 'PTB', MNJ: 'MNJ' };

/**
 * The PIN every fixture location uses for the offline override. PINs are at
 * least 8 digits (Limits.minOverridePinDigits, D-031).
 */
export const TEST_PIN = '24681357';

function location(code, name) {
  return {
    code,
    name,
    address: `${name} address`,
    phone: '0000000000',
    gstin: null,
    offlineLimitHours: 5,
    // Fixed salt keeps fixtures deterministic. The seed script uses a random one.
    overridePinHash: hashPin(TEST_PIN, Buffer.from(`fixture-${code}`)),
    overrideExtensionHours: 2,
    maxDiscountPct: 20,
    receiptFooter: 'Thank you!',
    // The last device number handed out; 0 for a new location (D-004).
    nextDeviceNo: 0,
    active: true,
  };
}

/** locations/{loc} */
export const LOCATIONS = {
  [LOC.PTB]: location(LOC.PTB, 'Test Store PTB'),
  [LOC.MNJ]: location(LOC.MNJ, 'Test Store MNJ'),
};

/**
 * The test actors. `uid: null` means an unauthenticated context. `doc` is the
 * users/{uid} doc seeded for that actor, without timestamps; null means no
 * doc is seeded.
 */
export const ACTORS = {
  admin: {
    uid: 'admin',
    doc: {
      name: 'Admin',
      email: 'admin@example.test',
      roleId: ROLE.ADMIN,
      locationId: null,
      active: true,
    },
  },
  smPtb: {
    uid: 'sm-ptb',
    doc: {
      name: 'Store Manager PTB',
      email: 'sm-ptb@example.test',
      roleId: ROLE.STORE_MANAGER,
      locationId: LOC.PTB,
      active: true,
    },
  },
  smMnj: {
    uid: 'sm-mnj',
    doc: {
      name: 'Store Manager MNJ',
      email: 'sm-mnj@example.test',
      roleId: ROLE.STORE_MANAGER,
      locationId: LOC.MNJ,
      active: true,
    },
  },
  disabled: {
    uid: 'sm-ptb-disabled',
    doc: {
      name: 'Disabled Store Manager PTB',
      email: 'sm-ptb-disabled@example.test',
      roleId: ROLE.STORE_MANAGER,
      locationId: LOC.PTB,
      active: false,
    },
  },
  cashierPtb: {
    uid: 'cashier-ptb',
    doc: {
      name: 'Cashier PTB',
      email: 'cashier-ptb@example.test',
      roleId: ROLE.CASHIER,
      locationId: LOC.PTB,
      active: true,
    },
  },
  counterPtb: {
    uid: 'counter-ptb',
    doc: {
      name: 'Stock Counter PTB',
      email: 'counter-ptb@example.test',
      roleId: ROLE.STOCK_COUNTER,
      locationId: LOC.PTB,
      active: true,
    },
  },
  // Signed in, but no users/{uid} doc (sign-in reports noProfile).
  noProfile: { uid: 'no-profile', doc: null },
  anonymous: { uid: null, doc: null },
};
