# fraiseql/starter-blog

A blog API built with FraiseQL: **posts, authors, tags, pagination, full-text search**.

## What's inside

| File | Purpose |
|------|---------|
| `schema.py` | Type and query definitions (authoring layer) |
| `fraiseql.toml` | Project and runtime configuration |
| `init.sql` | PostgreSQL tables, views, functions, and seed data |
| `docker-compose.yml` | One-command local stack |
| `.env.example` | Environment variable template |

## GraphQL API surface

```graphql
type Author { id, name, email, bio, avatarUrl, createdAt }
type Tag    { id, slug, label }
type Post   { id, title, slug, excerpt, content, author, tags, published, ... }

type Query {
  posts(limit, offset, published, authorId, tagSlug): [Post!]!
  post(id): Post
  postBySlug(slug): Post
  searchPosts(query, limit, offset): [Post!]!
  authors(limit, offset): [Author!]!
  author(id): Author
  tags: [Tag!]!
}

type Mutation {
  createPost(title, content, authorId, excerpt, published): Post!
  updatePost(id, title, content, excerpt, published): Post!
  addTagToPost(postId, tagSlug): Post!
}
```

## Quickstart (Docker)

```bash
cp .env.example .env

pip install fraiseql
python schema.py
fraiseql compile

docker compose up
```

API at **http://localhost:8080/graphql**.

## Quickstart (local binary)

```bash
cp .env.example .env && source .env
pip install fraiseql
python schema.py && fraiseql compile && fraiseql run
```

## Example queries

```graphql
# List published posts
query {
  posts(limit: 5, published: true) {
    title
    slug
    author { name }
    tags { slug label }
  }
}

# Full-text search
query {
  searchPosts(query: "FraiseQL PostgreSQL") {
    title
    excerpt
  }
}

# Create a post
mutation {
  createPost(
    title: "My new post"
    content: "FraiseQL makes this easy."
    authorId: 1
    published: true
  ) {
    id slug publishedAt
  }
}
```

## How full-text search works

`init.sql` adds a generated `tsvector` column (`search_tsv`) to the `posts` table, indexed with GIN. The `v_post_search` view exposes this. FraiseQL routes `searchPosts(query: "...")` to a `WHERE search_tsv @@ plainto_tsquery(...)` clause automatically.

## Next steps

- `starter-saas` — multi-tenant, auth, subscriptions, NATS
