Supabase self-hosted helper

Quickstart (development):

1. Start the Supabase development containers (Postgres with pgvector, Realtime, PostgREST, Studio):

```bash
docker-compose -f ../docker-compose.supabase.yml up -d
```

2. Wait for Postgres to be ready, then run the schema initialization (uses `SUPABASE_DB_URL` from `.env` or `.env.local`):

```bash
# ensure envs are loaded
export $(cat ../.env.local 2>/dev/null || cat ../.env.example | xargs)
psql "$SUPABASE_DB_URL" -f ../supabase/init.sql
```

Notes:
- This compose builds a Postgres image with `pgvector` installed for local development.
- Make sure `.env.local` or `.env.example` contains passwords without symbols (only letters/numbers) to avoid issues with shell parsing and clients.
- For production, follow the official Supabase self-hosting guide and use secure secrets management.
