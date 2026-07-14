/**
 * Postgres query layer for the Node backend (replaces @supabase/supabase-js).
 */
function createDb(pool) {
  if (!pool) return null;
  return {
    from(table) {
      return new QueryBuilder(pool, table);
    },
    async rpc(functionName, params = {}) {
      try {
        const keys = Object.keys(params);
        const values = Object.values(params);
        const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
        const sql = `SELECT * FROM ${functionName}(${placeholders})`;
        const result = await pool.query(sql, values);
        return { data: result.rows, error: null };
      } catch (error) {
        return { data: null, error };
      }
    },
  };
}

class QueryBuilder {
  constructor(pool, table) {
    this.pool = pool;
    this.table = table;
    this.op = 'select';
    this.columns = '*';
    this.filters = [];
    this.orders = [];
    this.limitVal = null;
    this.body = null;
    this.single = false;
    this.onConflict = null;
  }

  select(columns = '*') {
    this.columns = columns;
    return this;
  }

  insert(values) {
    this.op = 'insert';
    this.body = values;
    return this;
  }

  update(values) {
    this.op = 'update';
    this.body = values;
    return this;
  }

  upsert(values, options = {}) {
    this.op = 'upsert';
    this.body = values;
    this.onConflict = options.onConflict || null;
    return this;
  }

  delete() {
    this.op = 'delete';
    return this;
  }

  eq(column, value) {
    this.filters.push({ column, op: '=', value });
    return this;
  }

  ilike(column, value) {
    this.filters.push({ column, op: 'ilike', value });
    return this;
  }

  order(column, { ascending = true } = {}) {
    this.orders.push({ column, ascending });
    return this;
  }

  limit(count) {
    this.limitVal = count;
    return this;
  }

  maybeSingle() {
    this.single = true;
    this.limitVal = 1;
    return this;
  }

  then(resolve, reject) {
    return this.execute().then(resolve, reject);
  }

  async execute() {
    try {
      const data = await this.run();
      if (this.single) {
        return { data: data.length > 0 ? data[0] : null, error: null };
      }
      return { data, error: null };
    } catch (error) {
      if (this.single) return { data: null, error };
      return { data: null, error };
    }
  }

  async run() {
    if (this.op === 'select') {
      return this.runSelect();
    }
    if (this.op === 'insert') {
      return this.runInsert(false);
    }
    if (this.op === 'update') {
      return this.runUpdate();
    }
    if (this.op === 'upsert') {
      return this.runInsert(true);
    }
    if (this.op === 'delete') {
      return this.runDelete();
    }
    throw new Error(`Unsupported operation: ${this.op}`);
  }

  async runSelect() {
    const join = parseEmbeddedSelect(this.table, this.columns);
    if (join) {
      return this.runEmbeddedSelect(join);
    }

    const { clause, values } = buildWhere(this.filters, 1);
    let sql = `SELECT ${quoteColumns(this.columns)} FROM ${quoteIdent(this.table)}`;
    if (clause) sql += ` WHERE ${clause}`;
    if (this.orders.length > 0) {
      sql += ` ORDER BY ${this.orders
        .map((o) => `${quoteIdent(o.column)} ${o.ascending ? 'ASC' : 'DESC'}`)
        .join(', ')}`;
    }
    if (this.limitVal != null) sql += ` LIMIT ${Number(this.limitVal)}`;
    const result = await this.pool.query(sql, values);
    return result.rows;
  }

  async runEmbeddedSelect(join) {
    const { clause, values } = buildWhere(this.filters, 2);
    let sql =
      `SELECT ${join.parentAlias}.*, ${join.embedAlias}.${quoteIdent(join.embedColumn)} AS ${quoteIdent(`__embed_${join.embedColumn}`)} ` +
      `FROM ${quoteIdent(this.table)} ${join.parentAlias} ` +
      `LEFT JOIN ${quoteIdent(join.embedTable)} ${join.embedAlias} ON ${join.joinSql}`;
    if (clause) sql += ` WHERE ${clause}`;
    if (this.limitVal != null) sql += ` LIMIT ${Number(this.limitVal)}`;
    const result = await this.pool.query(sql, values);
    return result.rows.map((row) => {
      const embedKey = `__embed_${join.embedColumn}`;
      const embedValue = row[embedKey];
      delete row[embedKey];
      row[join.embedTable] = { [join.embedColumn]: embedValue };
      return row;
    });
  }

  async runInsert(isUpsert) {
    const rows = Array.isArray(this.body) ? this.body : [this.body];
    const out = [];
    for (const row of rows) {
      const keys = Object.keys(row);
      const values = Object.values(row);
      const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
      let sql =
        `INSERT INTO ${quoteIdent(this.table)} (${keys.map(quoteIdent).join(', ')}) ` +
        `VALUES (${placeholders})`;
      if (isUpsert && this.onConflict) {
        const conflictCols = this.onConflict.split(',').map((c) => quoteIdent(c.trim()));
        const updates = keys
          .filter((k) => !this.onConflict.split(',').map((c) => c.trim()).includes(k))
          .map((k) => `${quoteIdent(k)} = EXCLUDED.${quoteIdent(k)}`)
          .join(', ');
        sql += ` ON CONFLICT (${conflictCols.join(', ')}) DO UPDATE SET ${updates || `${conflictCols[0]} = EXCLUDED.${conflictCols[0]}`}`;
      }
      sql += ' RETURNING *';
      const result = await this.pool.query(sql, values);
      out.push(...result.rows);
    }
    return out;
  }

  async runUpdate() {
    const keys = Object.keys(this.body || {});
    const setValues = Object.values(this.body || {});
    const setClause = keys.map((k, i) => `${quoteIdent(k)} = $${i + 1}`).join(', ');
    const { clause, values } = buildWhere(this.filters, keys.length + 1);
    const sql =
      `UPDATE ${quoteIdent(this.table)} SET ${setClause}` +
      (clause ? ` WHERE ${clause}` : '') +
      ' RETURNING *';
    const result = await this.pool.query(sql, [...setValues, ...values]);
    return result.rows;
  }

  async runDelete() {
    const { clause, values } = buildWhere(this.filters, 1);
    const sql =
      `DELETE FROM ${quoteIdent(this.table)}` + (clause ? ` WHERE ${clause}` : '') + ' RETURNING *';
    const result = await this.pool.query(sql, values);
    return result.rows;
  }
}

function parseEmbeddedSelect(table, columns) {
  const match = columns.match(/^(\w+)\s*\(\s*([^)]+)\s*\)$/);
  if (!match) return null;
  const embedTable = match[1];
  const embedColumn = match[2].split(',')[0].trim();
  if (table === 'app_users' && embedTable === 'staff') {
    return {
      parentAlias: 'p',
      embedAlias: 's',
      embedTable: 'staff',
      embedColumn,
      joinSql: 'p.staff_id = s.id',
    };
  }
  return null;
}

function buildWhere(filters, startIndex) {
  if (!filters.length) return { clause: '', values: [] };
  const parts = [];
  const values = [];
  let idx = startIndex;
  for (const f of filters) {
    if (f.op === 'ilike') {
      parts.push(`${quoteIdent(f.column)} ILIKE $${idx++}`);
      values.push(f.value);
    } else {
      parts.push(`${quoteIdent(f.column)} = $${idx++}`);
      values.push(f.value);
    }
  }
  return { clause: parts.join(' AND '), values };
}

function quoteIdent(name) {
  return `"${String(name).replace(/"/g, '""')}"`;
}

function quoteColumns(columns) {
  if (columns === '*') return '*';
  return columns
    .split(',')
    .map((c) => c.trim())
    .filter(Boolean)
    .map((c) => {
      if (c.includes('(')) return c;
      return quoteIdent(c);
    })
    .join(', ');
}

module.exports = { createDb };
