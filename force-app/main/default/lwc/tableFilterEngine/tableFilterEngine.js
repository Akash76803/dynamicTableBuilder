/**
 * tableFilterEngine.js  –  Full-featured client-side filter engine
 *
 * Supported operators
 * ───────────────────
 * Text / Lookup / LongText : contains · equals · not_equals · starts_with · ends_with
 *                            is_blank · is_not_blank
 * Number / Currency / %    : equals · not_equals · greater_than · less_than · gte · lte
 *                            between (uses valueMin / valueMax) · is_blank
 * Date / DateTime          : equals · before · after · between · is_blank
 * Time                     : equals · before · after · between
 * Picklist                 : equals · not_equals
 *                            includes  (any of selected array)
 *                            excludes  (none of selected array)
 * Boolean                  : is_true · is_false
 */

const str = (v) => (v == null ? "" : String(v));
const low = (v) => str(v).toLowerCase();
const num = (v) => (v == null ? NaN : Number(v));
const toMs = (v) => (v ? new Date(v).getTime() : NaN); // works for dates AND datetimes

/* ─── Operator implementations ─────────────────────────────────────────────── */
const OPS = {
  /* ── Text ─────────────────────────────────────────────────── */
  contains: (rv, fv) => low(rv).includes(low(fv)),
  equals: (rv, fv) => low(rv) === low(fv),
  not_equals: (rv, fv) => low(rv) !== low(fv),
  starts_with: (rv, fv) => low(rv).startsWith(low(fv)),
  ends_with: (rv, fv) => low(rv).endsWith(low(fv)),
  is_blank: (rv) => rv == null || str(rv).trim() === "",
  is_not_blank: (rv) => rv != null && str(rv).trim() !== "",

  /* ── Numeric ──────────────────────────────────────────────── */
  greater_than: (rv, fv) => num(rv) > num(fv),
  less_than: (rv, fv) => num(rv) < num(fv),
  gte: (rv, fv) => num(rv) >= num(fv),
  lte: (rv, fv) => num(rv) <= num(fv),

  /* ── Date / Time ──────────────────────────────────────────── */
  before: (rv, fv) => toMs(rv) < toMs(fv),
  after: (rv, fv) => toMs(rv) > toMs(fv),

  /* ── Between (number OR date/time) ───────────────────────── */
  between: (rv, _fv, filter) => {
    const { valueMin, valueMax } = filter || {};

    // Try numeric first
    const n = num(rv);
    const nMin = num(valueMin);
    const nMax = num(valueMax);
    if (!isNaN(n) && !isNaN(nMin) && !isNaN(nMax)) {
      return n >= nMin && n <= nMax;
    }

    // Fall back to date / datetime / time string comparison
    const d = toMs(rv);
    const dMin = toMs(valueMin);
    const dMax = toMs(valueMax);
    if (!isNaN(d) && !isNaN(dMin) && !isNaN(dMax)) {
      return d >= dMin && d <= dMax;
    }

    return true; // can't compare → pass through
  },

  /* ── Boolean ──────────────────────────────────────────────── */
  is_true: (rv) => rv === true || rv === "true" || rv === "1",
  is_false: (rv) => rv === false || rv === "false" || rv === "0",

  /* ── Multi-select picklist ─────────────────────────────────  */
  // includes: row value must match AT LEAST ONE selected value
  includes: (rv, fv) => {
    const vals = Array.isArray(fv) ? fv : fv != null ? [String(fv)] : [];
    if (!vals.length) return true;
    return vals.some((v) => low(rv) === low(v));
  },
  // excludes: row value must match NONE of the selected values
  excludes: (rv, fv) => {
    const vals = Array.isArray(fv) ? fv : fv != null ? [String(fv)] : [];
    if (!vals.length) return true;
    return vals.every((v) => low(rv) !== low(v));
  }
};

/* ─── Helpers ───────────────────────────────────────────────────────────────── */
function resolveValue(record, fieldPath) {
  if (!fieldPath || !record) return undefined;
  return fieldPath
    .split(".")
    .reduce((obj, key) => (obj != null ? obj[key] : undefined), record);
}

function testFilter(record, filter) {
  const { fieldName, soqlFieldPath, operator, values = [] } = filter;
  const fieldPath = soqlFieldPath || fieldName;
  const recordVal = resolveValue(record, fieldPath);

  let cleanOp = (operator || "").toLowerCase();
  if (cleanOp === "in") cleanOp = "includes";
  if (cleanOp === "not_in") cleanOp = "excludes";

  const opFn = OPS[cleanOp];
  if (!opFn) return true; // unknown operator → pass through

  const value = values.length > 0 ? values[0] : undefined;
  const valueMin = values.length > 0 ? values[0] : undefined;
  const valueMax = values.length > 1 ? values[1] : undefined;

  const enrichedFilter = {
    ...filter,
    value,
    valueMin,
    valueMax
  };

  const fv = cleanOp === "includes" || cleanOp === "excludes" ? values : value;

  const matchLabel = opFn(recordVal, fv, enrichedFilter);
  const recordValId = resolveValue(record, fieldPath + "_id");
  if (recordValId !== undefined) {
    const matchId = opFn(recordValId, fv, enrichedFilter);
    const isNegative = cleanOp.includes("not") || cleanOp.includes("exclude");
    if (isNegative) {
      return matchLabel && matchId;
    }
    return matchLabel || matchId;
  }
  return matchLabel;
}

/* ─── Public API ────────────────────────────────────────────────────────────── */
export function applyFilters(records, payload) {
  if (!records || !records.length || !payload) return records;

  const { logic = "AND", filters = [], customLogic = "" } = payload;
  const activeFilters = filters.filter((f) => f.fieldName && f.operator);
  if (!activeFilters.length) return records;

  return records.filter((record) => {
    if (logic === "OR") return activeFilters.some((f) => testFilter(record, f));
    if (logic === "CUSTOM")
      return _evalCustomLogic(record, activeFilters, customLogic);
    return activeFilters.every((f) => testFilter(record, f)); // AND
  });
}

/**
 * Evaluates a custom logic string like "1 AND (2 OR 3)".
 * Falls back to AND if the expression cannot be parsed.
 */
function _evalCustomLogic(record, filters, expr) {
  if (!expr || !expr.trim()) {
    return filters.every((f) => testFilter(record, f));
  }
  try {
    // Replace filter index tokens (1, 2 …) with their boolean results
    let boolExpr = expr
      .replace(/\bAND\b/gi, "&&")
      .replace(/\bOR\b/gi, "||")
      .replace(/\bNOT\b/gi, "!");

    filters.forEach((f, i) => {
      const result = testFilter(record, f);
      // Replace standalone number references (e.g. "1" → true/false)
      boolExpr = boolExpr.replace(
        new RegExp(`\\b${f.filterIndex || i + 1}\\b`, "g"),
        String(result)
      );
    });

    return parseBooleanExpression(boolExpr);
  } catch (_e) {
    // Fallback to AND
    return filters.every((f) => testFilter(record, f));
  }
}

function parseBooleanExpression(expr) {
  const tokens = tokenizeBooleanExpression(expr);
  let index = 0;

  function peek() {
    return tokens[index];
  }

  function consume(expected) {
    if (peek() !== expected) {
      throw new Error(`Expected ${expected}`);
    }
    index += 1;
  }

  function parsePrimary() {
    const token = peek();
    if (token === "true") {
      index += 1;
      return true;
    }
    if (token === "false") {
      index += 1;
      return false;
    }
    if (token === "(") {
      consume("(");
      const value = parseOr();
      consume(")");
      return value;
    }
    if (token === "!") {
      consume("!");
      return !parsePrimary();
    }
    throw new Error(`Unexpected token ${token || "EOF"}`);
  }

  function parseAnd() {
    let value = parsePrimary();
    while (peek() === "&&") {
      consume("&&");
      const right = parsePrimary();
      value = value && right;
    }
    return value;
  }

  function parseOr() {
    let value = parseAnd();
    while (peek() === "||") {
      consume("||");
      const right = parseAnd();
      value = value || right;
    }
    return value;
  }

  const result = parseOr();
  if (index !== tokens.length) {
    throw new Error(`Unexpected trailing token ${peek()}`);
  }
  return Boolean(result);
}

function tokenizeBooleanExpression(expr) {
  const tokens = [];
  let index = 0;
  while (index < expr.length) {
    const ch = expr[index];
    if (/\s/.test(ch)) {
      index += 1;
      continue;
    }
    if (ch === "(" || ch === ")" || ch === "!") {
      tokens.push(ch);
      index += 1;
      continue;
    }
    if (expr.slice(index, index + 2) === "&&") {
      tokens.push("&&");
      index += 2;
      continue;
    }
    if (expr.slice(index, index + 2) === "||") {
      tokens.push("||");
      index += 2;
      continue;
    }
    if (expr.slice(index, index + 4).toLowerCase() === "true") {
      tokens.push("true");
      index += 4;
      continue;
    }
    if (expr.slice(index, index + 5).toLowerCase() === "false") {
      tokens.push("false");
      index += 5;
      continue;
    }
    throw new Error(`Invalid character ${ch}`);
  }
  return tokens;
}