const express = require('express')
const app = express()
const port = process.env.PORT || 3000

app.get('/', (req, res) => {
  res.setHeader('Content-Type', 'text/html')
  res.send(`<!doctype html><html><head><title>OpenDiscourse Demo</title></head><body><h1>OpenDiscourse Demo</h1><p>Welcome — core stack running.</p></body></html>`)
})

app.listen(port, () => console.log(`web demo listening on ${port}`))
