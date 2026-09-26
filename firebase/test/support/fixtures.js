// Fixture data for the rules tests: roles, users and locations.
//
// Roles are read from packages/core/lib/src/permissions.dart (Permission and
// SeedRoles), so the rules suite always tests the same permission sets the
// apps and the seed script use. If that file changes shape, parsing fails
// loudly instead of drifting.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { pbkdf2Sync } from 'node:crypto';

const PERMISSIONS_DART = fileURLToPath(
  new URL('../../../packages/core/lib/src/permissions.dart', import.meta.url),
);

/** Parses Permission constants and SeedRoles lists out of permissions.dart. */
export function parsePermissionsDart(source) {
  const block = (name) => {
    const m = source.match(
      new RegExp(`abstract final class ${name} \\{([\\s\\S]*?)\\n\\}`),
    );
    if (!m) throw new Error(`permissions.dart: class ${name} not found`);
    return m[1];
  };
  const listBody = (body, name) => {
    const m = body.match(
      new RegExp(`static const List<String> ${name} =\\s*([\\s\\S]*?);`),
    );
    if (!m) throw new Error(`permissions.dart: list ${name} not found`);
    return m[1];
  };

  const permBlock = block('Permission');
  const constants = {};
  for (const m of permBlock.matchAll(
    /static const String (\w+) = '([^']+)';/g,
  )) {
    constants[m[1]] = m[2];
  }
  if (Object.keys(constants).length === 0) {
    throw new Error('permissions.dart: no Permission constants found');
  }
  const resolve = (ident) => {
    const name = ident.replace(/^Permission\./, '');
    if (!(name in constants)) {
      throw new Error(`permissions.dart: unknown permission ${ident}`);
    }
    return constants[name];
  };
  const identifiers = (expr) =>
    [...expr.matchAll(/[\w.]+/g)].map((m) => m[0]);

  const all = identifiers(listBody(permBlock, 'all').replace(/[[\]]/g, ''))
    .map(resolve);

  const rolesBlock = block('SeedRoles');
  const roleId = (name) => {
    const m = rolesBlock.match(
      new RegExp(`static const String ${name} = '([^']+)';`),
    );
    if (!m) throw new Error(`permissions.dart: SeedRoles.${name} not found`);
    return m[1];
  };
  const roleList = (name) => {
    const expr = listBody(rolesBlock, name).trim();
    if (expr === 'Permission.all') return [...all];
    return identifiers(expr.replace(/[[\]]/g, '')).map(resolve);
  };

  return {
    all,
    adminId: roleId('adminId'),
    storeManagerId: roleId('storeManagerId'),
    adminPermissions: roleList('adminPermissions'),
    storeManagerPermissions: roleList('storeManagerPermissions'),
  };
}

export const PERMS = parsePermissionsDart(
  readFileSync(PERMISSIONS_DART, 'utf8'),
);

export const ROLE = {
  ADMIN: PERMS.adminId,
  STORE_MANAGER: PERMS.storeManagerId,
};

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
};

export const LOC = { PTB: 'PTB', MNJ: 'MNJ' };

/**
 * The PIN every fixture location uses for the offline override. PINs are at
 * least 8 digits (Limits.minOverridePinDigits, D-031).
 */
export const TEST_PIN = '24681357';

/** PBKDF2-SHA256, 100k iterations, `salt$hash` in base64 (02-DATA-MODEL). */
export function hashPin(pin, salt) {
  const hash = pbkdf2Sync(pin, salt, 100_000, 32, 'sha256');
  return `${salt.toString('base64')}$${hash.toString('base64')}`;
}

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
  // Signed in, but no users/{uid} doc (sign-in reports noProfile).
  noProfile: { uid: 'no-profile', doc: null },
  anonymous: { uid: null, doc: null },
};
