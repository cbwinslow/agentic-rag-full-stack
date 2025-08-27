const express = require('express')
const bodyParser = require('body-parser')
const app = express()
const port = process.env.PORT || 8000

app.use(bodyParser.json())

app.get('/api/ping', (req, res) => res.json({ok:true, ts: Date.now()}))

app.post('/api/rag/query', (req, res) => {
  const { query } = req.body || {}
  const demo = {
    answer: `Demo answer for: ${query || '<empty>'}`,
    citations: [
      { title: 'Sample Source A', url: 'https://example.org/a', score: 0.92 },
      { title: 'Sample Source B', url: 'https://example.org/b', score: 0.87 }
    ]
  }
  res.json(demo)
})

app.listen(port, () => console.log(`api listening on ${port}`))
