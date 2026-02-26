-- Blog starter schema
-- FraiseQL reads from views (v_*) and calls functions (fn_*)

-- ── Tables ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tb_author (
    id         SERIAL,
    name       TEXT        NOT NULL,
    email      TEXT        NOT NULL UNIQUE,
    bio        TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_author PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS tb_tag (
    id         SERIAL,
    identifier TEXT NOT NULL UNIQUE,
    label      TEXT NOT NULL,
    CONSTRAINT pk_tag PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS tb_post (
    id           SERIAL,
    title        TEXT        NOT NULL,
    identifier   TEXT        NOT NULL UNIQUE,
    excerpt      TEXT,
    content      TEXT        NOT NULL DEFAULT '',
    author_id    INTEGER     NOT NULL,
    published    BOOLEAN     NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv   TSVECTOR    GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))
    ) STORED,
    CONSTRAINT pk_post           PRIMARY KEY (id),
    CONSTRAINT fk_post_author_id FOREIGN KEY (author_id) REFERENCES tb_author(id)
);

CREATE TABLE IF NOT EXISTS tb_post_tag (
    post_id INTEGER NOT NULL,
    tag_id  INTEGER NOT NULL,
    CONSTRAINT pk_post_tag         PRIMARY KEY (post_id, tag_id),
    CONSTRAINT fk_post_tag_post_id FOREIGN KEY (post_id) REFERENCES tb_post(id) ON DELETE CASCADE,
    CONSTRAINT fk_post_tag_tag_id  FOREIGN KEY (tag_id)  REFERENCES tb_tag(id)  ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS tb_post_search_idx  ON tb_post     USING GIN(search_tsv);
CREATE INDEX IF NOT EXISTS tb_post_tag_tag_idx ON tb_post_tag(tag_id);

-- ── Views ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_author AS
SELECT
    id,
    name,
    email,
    bio,
    avatar_url,
    created_at::TEXT AS created_at
FROM tb_author;

CREATE OR REPLACE VIEW v_tag AS
SELECT id, identifier, label FROM tb_tag;

CREATE OR REPLACE VIEW v_post AS
SELECT
    p.id,
    p.title,
    p.identifier,
    p.excerpt,
    p.content,
    p.author_id,
    row_to_json(a)::jsonb  AS author,
    COALESCE(
        json_agg(t ORDER BY t.identifier) FILTER (WHERE t.id IS NOT NULL),
        '[]'::json
    )::jsonb               AS tags,
    p.published,
    p.published_at::TEXT   AS published_at,
    p.created_at::TEXT     AS created_at,
    p.updated_at::TEXT     AS updated_at
FROM tb_post p
JOIN tb_author a ON a.id = p.author_id
LEFT JOIN tb_post_tag pt ON pt.post_id = p.id
LEFT JOIN tb_tag t ON t.id = pt.tag_id
GROUP BY p.id, a.id;

CREATE OR REPLACE VIEW v_post_search AS
SELECT
    p.id,
    p.title,
    p.identifier,
    p.excerpt,
    p.content,
    p.author_id,
    row_to_json(a)::jsonb AS author,
    -- tags intentionally omitted from search results (avoids GROUP BY; fetch via post(id))
    '[]'::jsonb           AS tags,
    p.published,
    p.published_at::TEXT  AS published_at,
    p.created_at::TEXT    AS created_at,
    p.updated_at::TEXT    AS updated_at,
    p.search_tsv
FROM tb_post p
JOIN tb_author a ON a.id = p.author_id
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
    v_identifier TEXT;
    v_id         INTEGER;
BEGIN
    v_identifier := trim('-' FROM lower(regexp_replace(p_title, '[^a-zA-Z0-9]+', '-', 'g')));
    INSERT INTO tb_post (title, identifier, content, author_id, excerpt, published, published_at)
    VALUES (
        p_title, v_identifier, p_content, p_author_id, p_excerpt,
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
    UPDATE tb_post SET
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
    p_post_id        INTEGER,
    p_tag_identifier TEXT
) RETURNS SETOF v_post AS $$
DECLARE
    v_tag_id INTEGER;
BEGIN
    INSERT INTO tb_tag (identifier, label)
    VALUES (p_tag_identifier, initcap(replace(p_tag_identifier, '-', ' ')))
    ON CONFLICT (identifier) DO NOTHING;

    SELECT id INTO v_tag_id FROM tb_tag WHERE identifier = p_tag_identifier;

    -- Tag label is derived from identifier on first creation only.
    -- If the tag already exists, the existing label is kept unchanged.
    INSERT INTO tb_post_tag (post_id, tag_id) VALUES (p_post_id, v_tag_id)
    ON CONFLICT (post_id, tag_id) DO NOTHING;

    RETURN QUERY SELECT * FROM v_post WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql;

-- ── Seed data ─────────────────────────────────────────────────────────────────

INSERT INTO tb_author (name, email, bio) VALUES
    ('Alice Martin', 'alice@example.com', 'Tech writer and open-source enthusiast.'),
    ('Bob Chen',     'bob@example.com',   'Backend engineer, database nerd.')
ON CONFLICT (email) DO NOTHING;

INSERT INTO tb_tag (identifier, label) VALUES
    ('graphql',    'GraphQL'),
    ('postgresql', 'PostgreSQL'),
    ('tutorial',   'Tutorial')
ON CONFLICT (identifier) DO NOTHING;

INSERT INTO tb_post (title, identifier, content, author_id, published, published_at) VALUES
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
ON CONFLICT (identifier) DO NOTHING;
