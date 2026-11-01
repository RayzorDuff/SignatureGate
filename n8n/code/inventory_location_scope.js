// Pure filter helper for the inventory Code node. No deployment configuration.
function inventoryLocationScope(query, locations) {
  const q = query || {};
  const keys = ['storage_locations_json', 'storage_locations', 'storage_location'];
  const requested = keys.some(key => Object.prototype.hasOwnProperty.call(q, key)) ||
    String(q.require_location_scope || '').toLowerCase() === 'true';
  if (!requested) return true;

  let allowed = [];
  if (Object.prototype.hasOwnProperty.call(q, 'storage_locations_json')) {
    try {
      allowed = JSON.parse(q.storage_locations_json);
      if (!Array.isArray(allowed)) return false;
    } catch (_) {
      return false;
    }
  } else if (q.storage_locations) {
    allowed = String(q.storage_locations).split(',');
  } else if (q.storage_location) {
    allowed = [q.storage_location];
  }
  const grants = new Set(allowed.map(value => String(value).trim().toLowerCase()).filter(Boolean));
  const rows = Array.isArray(locations) ? locations : [locations];
  return grants.size > 0 && rows.some(value => grants.has(String(value || '').trim().toLowerCase()));
}
