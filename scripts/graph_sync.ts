import { query } from '../lib/db'
import { runCypher, closeDriver } from '../lib/neo4jClient'

async function syncEntities() {
  const res = await query('SELECT id, type, canonical_id, name FROM entities')
  for (const row of res.rows) {
    const { id, type, canonical_id, name } = row
    const uid = canonical_id || `${type}:${id}`
    await runCypher('MERGE (e:Entity {uid:$uid}) SET e.name=$name, e.type=$type', { uid, name, type })
  }
}

async function syncRelations() {
  const res = await query('SELECT r.id, s.type AS src_type, s.canonical_id AS src_cid, s.id AS src_id, d.type AS dst_type, d.canonical_id AS dst_cid, d.id AS dst_id, r.rel_type FROM relations r JOIN entities s ON r.src_entity_id = s.id JOIN entities d ON r.dst_entity_id = d.id')
  for (const row of res.rows) {
    const srcUid = row.src_cid || `${row.src_type}:${row.src_id}`
    const dstUid = row.dst_cid || `${row.dst_type}:${row.dst_id}`
    await runCypher('MERGE (a:Entity {uid:$a}) MERGE (b:Entity {uid:$b}) MERGE (a)-[r:REL {type:$t}]->(b) SET r._src = $a, r._dst = $b', { a: srcUid, b: dstUid, t: row.rel_type })
  }
}

async function main() {
  await syncEntities()
  await syncRelations()
  await closeDriver()
}

if (require.main === module) main().catch((e)=>{console.error(e); process.exit(1)})
