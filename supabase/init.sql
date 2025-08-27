-- Supabase setup for GraphRAG (self-hosted)
-- Run this in the Supabase SQL editor or psql connected to the Supabase Postgres DB

-- Ensure pgvector extension is available for vector search
CREATE EXTENSION IF NOT EXISTS vector;

-- Table for text chunks (for embeddings)
-- Use 384-dim vectors by default for local MiniLM model (all-MiniLM-L6-v2)
CREATE TABLE IF NOT EXISTS chunks (
  id BIGSERIAL PRIMARY KEY,
  document_id BIGINT REFERENCES documents(id) ON DELETE CASCADE,
  char_start INT,
  char_end INT,
  text TEXT,
  tokens INT DEFAULT 0,
  embedding vector(384),
  created_at timestamptz DEFAULT now()
);

-- Entities and relations for NER and graph linking
CREATE TABLE IF NOT EXISTS entities (
  id BIGSERIAL PRIMARY KEY,
  canonical TEXT NOT NULL,
  mention TEXT,
  type TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS relations (
  id BIGSERIAL PRIMARY KEY,
  subject BIGINT REFERENCES entities(id) ON DELETE CASCADE,
  object BIGINT REFERENCES entities(id) ON DELETE CASCADE,
  predicate TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Create auth roles table example
-- Tables for documents and access control
CREATE TABLE IF NOT EXISTS documents (
  id BIGSERIAL PRIMARY KEY,
  owner UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  source TEXT NOT NULL,
  external_id TEXT NOT NULL,
  title TEXT,
  sha256 CHAR(64) UNIQUE,
  text_clean TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  UNIQUE (source, external_id)
);

-- Enable row level security and policy examples
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- Admin role can do everything
CREATE POLICY "admin_full_access" ON documents FOR ALL TO public USING (true) WITH CHECK (true);

-- Example: owners can select/insert/update their documents
CREATE POLICY "owners_can_manage" ON documents FOR ALL USING (auth.uid() = owner) WITH CHECK (auth.uid() = owner);

-- Public read policy (for viewer role you might create a custom role/claim)
CREATE POLICY "public_read" ON documents FOR SELECT USING (true);

-- Add index on metadata
CREATE INDEX IF NOT EXISTS documents_metadata_idx ON documents USING gin (metadata);
