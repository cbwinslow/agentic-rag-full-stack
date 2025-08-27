from fastapi import FastAPI
from pydantic import BaseModel, HttpUrl
app = FastAPI(title='ingest')

class PDFIn(BaseModel):
    url: HttpUrl

@app.get('/health')
def health():
    return {'status':'ok'}

@app.post('/ingest/pdf')
def ingest_pdf(payload: PDFIn):
    # This is a stub: a real service would fetch the URL, OCR/parse, chunk, embed
    return {'ingested': payload.url, 'chunks': 3}
