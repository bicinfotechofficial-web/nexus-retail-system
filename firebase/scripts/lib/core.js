// What firebase/ reads from packages/core, so the rules suite and the seed
// script can't drift from the apps: the permission sets (permissions.dart),
// the list caps (limits.dart), and the override PIN hash (02-DATA-MODEL).
// If a Dart file changes shape, parsing fails loudly instead of drifting.

import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const CORE_SRC = fileURLToPath(new URL('../../../packages/core/lib/src/', import.meta.url));

/** Parses Permission constants and SeedRoles lists out of permissions.dart. */
export function parsePermissionsDart(source) {
  const block = (name) => {
    const m = source.match(new RegExp(`abstract final class ${name} \\{([\\s\\S]*?)\\n\\}`));
    if (!m) throw new Error(`permissions.dart: class ${name} not found`);
    return m[1];
  };
  const listBody = (body, name) => {
    const m = body.match(new RegExp(`static const List<String> ${name} =\\s*([\\s\\S]*?);`));
    if (!m) throw new Error(`permissions.dart: list ${name} not found`);
    return m[1];
  };

  const permBlock = block('Permission');
  const constants = {};
  for (const m of permBlock.matchAll(/static const String (\w+) = '([^']+)';/g)) {
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
  const identifiers = (expr) => [...expr.matchAll(/[\w.]+/g)].map((m) => m[0]);

  const all = identifiers(listBody(permBlock, 'all').replace(/[[\]]/g, '')).map(resolve);

  const rolesBlock = block('SeedRoles');
  const roleId = (name) => {
    const m = rolesBlock.match(new RegExp(`static const String ${name} = '([^']+)';`));
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

/** The permission sets in packages/core/lib/src/permissions.dart. */
export function readPermissions() {
  return parsePermissionsDart(readFileSync(`${CORE_SRC}permissions.dart`, 'utf8'));
}

/** `Limits` in packages/core/lib/src/limits.dart, as `{ maxBillLines: 15, ... }`. */
export function readLimits() {
  const source = readFileSync(`${CORE_SRC}limits.dart`, 'utf8');
  const limits = Object.fromEntries([...source.matchAll(/static const int (\w+) = (\d+);/g)].map((m) => [m[1], Number(m[2])]));
  for (const name of ['maxBillLines', 'maxMovementLines', 'maxPayments', 'maxRefunds', 'minOverridePinDigits']) {
    if (!Number.isInteger(limits[name])) throw new Error(`limits.dart: Limits.${name} not found`);
  }
  return limits;
}

export const PIN_HASH_ITERATIONS = 100_000;
export const PIN_HASH_BYTES = 32;
export const PIN_SALT_BYTES = 16;

/**
 * The override PIN hash (02-DATA-MODEL locations): PBKDF2-SHA256 over the
 * PIN's UTF-8 bytes, 100k iterations, a 32-byte key, stored as
 * `base64(salt)$base64(key)`. A random 16-byte salt unless one is given.
 */
export function hashPin(pin, salt = randomBytes(PIN_SALT_BYTES)) {
  const hash = pbkdf2Sync(pin, salt, PIN_HASH_ITERATIONS, PIN_HASH_BYTES, 'sha256');
  return `${salt.toString('base64')}$${hash.toString('base64')}`;
}

/** Whether `pin` matches a `salt$hash` made by hashPin(). */
export function verifyPin(pin, stored) {
  const [salt, hash] = String(stored).split('$');
  if (!salt || !hash) return false;
  return hashPin(pin, Buffer.from(salt, 'base64')) === stored;
}
