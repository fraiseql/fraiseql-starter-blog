-- Blog starter schema
-- FraiseQL reads from views (v_*) and calls functions (fn_*)

-- ── Tables ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS authors (
    id         SERIAL PRIMARY KEY,
    name       TEXT        NOT NULL,
    email      TEXT        NOT NULL UNIQUE,
    bio        TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tags (
    id    SERIAL PRIMARY KEY,
    slug  TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS posts (
    id           SERIAL PRIMARY KEY,
    title        TEXT        NOT NULL,
    slug         TEXT        NOT NULL UNIQUE,
    excerpt      TEXT,
    content      TEXT        NOT NULL DEFAULT '',
    author_id    INTEGER     NOT NULL REFERENCES authors(id),
    published    BOOLEAN     NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Full-text search vector (updated by trigger)
    search_tsv   TSVECTOR    GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))
    ) STORED
);

CREATE TABLE IF NOT EXISTS post_tags (
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);

CREATE INDEX IF NOT EXISTS posts_search_idx ON posts USING GIN(search_tsv);

-- ── Views ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_author AS
SELECT
    id,
    name,
    email,
    bio,
    avatar_url,
    created_at::TEXT AS created_at
FROM authors;

CREATE OR REPLACE VIEW v_tag AS
SELECT id, slug, label FROM tags;

CREATE OR REPLACE VIEW v_post AS
SELECT
    p.id,
    p.title,
    p.slug,
    p.excerpt,
    p.content,
    p.author_id,
    row_to_json(a)::jsonb  AS author,
    COALESCE(
        json_agg(t ORDER BY t.slug) FILTER (WHERE t.id IS NOT NULL),
        '[]'::json
    )::jsonb               AS tags,
    p.published,
    p.published_at::TEXT   AS published_at,
    p.created_at::TEXT     AS created_at,
    p.updated_at::TEXT     AS updated_at
FROM posts p
JOIN authors a ON a.id = p.author_id
LEFT JOIN post_tags pt ON pt.post_id = p.id
LEFT JOIN tags t ON t.id = pt.tag_id
GROUP BY p.id, a.id;

CREATE OR REPLACE VIEW v_post_search AS
SELECT
    p.id,
    p.title,
    p.slug,
    p.excerpt,
    p.content,
    p.author_id,
    row_to_json(a)::jsonb AS author,
    '[]'::jsonb           AS tags,
    p.published,
    p.published_at::TEXT  AS published_at,
    p.created_at::TEXT    AS created_at,
    p.updated_at::TEXT    AS updated_at,
    p.search_tsv
FROM posts p
JOIN authors a ON a.id = p.author_id
WHERE p.published = true;

-- ── Functions ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_create_post(
    p_title     TEXT,
    p_content   TEXT,
    p_author_id INTEGER,
    p_excerpt   TEXT    DEFAULT NULL,
    p_published BOOLEAN DEFAULT false
) RETURNS SETOF v_post AS $$
DECLARE
    v_slug TEXT;
    v_id   INTEGER;
BEGIN
    v_slug := lower(regexp_replace(p_title, '[^a-zA-Z0-9]+', '-', 'g'));
    INSERT INTO posts (title, slug, content, author_id, excerpt, published, published_at)
    VALUES (
        p_title, v_slug, p_content, p_author_id, p_excerpt,
        p_published,
        CASE WHEN p_published THEN now() ELSE NULL END
    )
    RETURNING id INTO v_id;
    RETURN QUERY SELECT * FROM v_post WHERE id = v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_update_post(
    p_id        INTEGER,
    p_title     TEXT    DEFAULT NULL,
    p_content   TEXT    DEFAULT NULL,
    p_excerpt   TEXT    DEFAULT NULL,
    p_published BOOLEAN DEFAULT NULL
) RETURNS SETOF v_post AS $$
BEGIN
    UPDATE posts SET
        title        = COALESCE(p_title,     title),
        content      = COALESCE(p_content,   content),
        excerpt      = COALESCE(p_excerpt,   excerpt),
        published    = COALESCE(p_published, published),
        published_at = CASE
                           WHEN p_published = true AND NOT published THEN now()
                           ELSE published_at
                       END,
        updated_at   = now()
    WHERE id = p_id;
    RETURN QUERY SELECT * FROM v_post WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_add_tag_to_post(
    p_post_id  INTEGER,
    p_tag_slug TEXT
) RETURNS SETOF v_post AS $$
DECLARE
    v_tag_id INTEGER;
BEGIN
    INSERT INTO tags (slug, label)
    VALUES (p_tag_slug, initcap(replace(p_tag_slug, '-', ' ')))
    ON CONFLICT (slug) DO NOTHING;

    SELECT id INTO v_tag_id FROM tags WHERE slug = p_tag_slug;

    INSERT INTO post_tags (post_id, tag_id) VALUES (p_post_id, v_tag_id)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM v_post WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql;

-- ── Seed data ─────────────────────────────────────────────────────────────────

INSERT INTO authors (name, email, bio) VALUES
    ('Alice Martin', 'alice@example.com', 'Tech writer and open-source enthusiast.'),
    ('Bob Chen',    'bob@example.com',   'Backend engineer, database nerd.')
ON CONFLICT DO NOTHING;

INSERT INTO tags (slug, label) VALUES
    ('graphql',    'GraphQL'),
    ('postgresql', 'PostgreSQL'),
    ('tutorial',   'Tutorial')
ON CONFLICT DO NOTHING;

INSERT INTO posts (title, slug, content, author_id, published, published_at) VALUES
    (
        'Getting started with FraiseQL',
        'getting-started-with-fraiseql',
        'FraiseQL compiles your GraphQL schema to optimized SQL at build time...',
        1, true, now()
    ),
    (
        'PostgreSQL views as a GraphQL layer',
        'postgresql-views-graphql-layer',
        'Using views to expose your data model to FraiseQL is straightforward...',
        2, true, now() - interval '7 days'
    )
ON CONFLICT DO NOTHING;
