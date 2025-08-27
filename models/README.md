Pydantic models and converters
=============================

This package contains strongly-typed Pydantic v2 models for the project's
database tables and DTOs. Use `models.schemas` to import types like
`Document`, `Chunk`, `Entity`, and service DTOs such as `PDFIn` / `IngestResult`.

Quick usage examples
--------------------

```python
from models.schemas import PDFIn, IngestResult
from models.converters import document_from_row

# Validate input
payload = PDFIn.model_validate({'url': 'https://example.com/doc.pdf'})

# Convert DB row
row = {'id':1, 'title':'Sample', 'source':'import'}
doc = document_from_row(row)
```

If you use SQL libraries that return `Row` objects, convert to dicts before
passing to the converters.
