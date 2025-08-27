import fs from 'fs'
import { Pool } from 'pg'
import path from 'path'

async function main() {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'db', 'schema.sql'), 'utf8')
  const pool = new Pool({
    connectionString: process.env.SUPABASE_DB_URL || process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/graphrag'
  })
  const client = await pool.connect()
  try {
    console.log('Running migrations...')
    await client.query(sql)
    console.log('Migrations applied')
  } finally {
    client.release()
    await pool.end()
  }
}

if (require.main === module) main().catch((e) => { console.error(e); process.exit(1) })
