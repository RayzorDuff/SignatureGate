// Only the reviewed bootstrap's psql controls and top-level transaction wrappers.
export function schemaSQL(text) {
  const lines=text.split('\n');
  if(lines.some(line=>line.startsWith('\\') && !/^\\(?:(?:un)?restrict\b|set ON_ERROR_STOP on$)/.test(line)))
    throw new Error('Review unexpected schema meta-command');
  return lines.filter(line=>!line.startsWith('\\') && !['BEGIN;','COMMIT;'].includes(line.trim())).join('\n');
}
