from fastapi import FastAPI
from models.schemas import PDFIn, IngestResult

app = FastAPI(title='ingest')


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.post('/ingest/pdf', response_model=IngestResult)
def ingest_pdf(payload: PDFIn):
    # This is a stub: a real service would fetch the URL, OCR/parse, chunk, embed,
    # normalize outputs into Chunk models and persist them. For now return a
    # typed IngestResult so callers get a validated response shape.
    return IngestResult(ingested=payload.url, chunks=3)
