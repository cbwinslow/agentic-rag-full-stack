import crypto from 'crypto'
import { query } from '../lib/db'

/**
 * Split text into chunks of approximately `chunkSize` characters.
 */
async function chunkText(text: string, chunkSize = 1000): Promise<string[]> {
  const chunks: string[] = []
  for (let i = 0; i < text.length; i += chunkSize) {
    chunks.push(text.slice(i, Math.min(i + chunkSize, text.length)))
  }
  return chunks
}

async function persistDocument(source: string, external_id: string, title: string, text: string): Promise<string> {
  const sha = crypto.createHash('sha256').update(text).digest('hex')
  const insertDoc = `INSERT INTO documents (source, external_id, title, sha256, text_raw) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (source, external_id) DO UPDATE SET title=EXCLUDED.title RETURNING id`;
  const r = await query(insertDoc, [source, external_id, title, sha, text])
  return r.rows[0].id
}

async function persistChunks(documentId: string, chunks: string[]): Promise<void> {
  const insert = `INSERT INTO chunks (document_id, char_start, char_end, text, tokens) VALUES ($1,$2,$3,$4,$5)`
  for (let i = 0; i < chunks.length; i++) {
    const c = chunks[i]
    const start = i * c.length
    const end = start + c.length
    const tokens = Math.max(1, Math.ceil(c.length / 4))
    await query(insert, [documentId, start, end, c, tokens])
  }
}

export async function processAndStore(source: string, external_id: string, title: string, text: string) {
  try {
    const docId = await persistDocument(source, external_id, title, text)
    const chunks = await chunkText(text, 1200)
    await persistChunks(docId, chunks)
    return { docId, chunkCount: chunks.length }
  } catch (err) {
    console.error('processAndStore error', err)
    throw err
  }
}

// CLI entry: node ./dist/worker/index.js or ts-node
if (require.main === module) {
  ;(async () => {
    const sample = 'This is a sample ingestion worker run. Replace with real ingestion.'
    try {
      const out = await processAndStore('local', 'sample-1', 'Sample Document', sample)
      // eslint-disable-next-line no-console
      console.log('stored', out)
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e)
      process.exit(1)
    }
  })()
}
