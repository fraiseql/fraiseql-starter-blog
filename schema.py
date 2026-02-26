"""FraiseQL Blog Starter — schema definition.

Demonstrates: multiple related types, pagination, full-text search, tags.

Run this to generate schema.json:
    python schema.py

Then compile and run:
    fraiseql compile
    fraiseql run
"""

import fraiseql


@fraiseql.type
class Author:
    """A blog author."""

    id: int
    name: str
    email: str
    bio: str | None
    avatar_url: str | None
    created_at: str


@fraiseql.type
class Tag:
    """A content tag."""

    id: int
    identifier: str
    label: str


@fraiseql.type
class Post:
    """A blog post."""

    id: int
    title: str
    identifier: str
    excerpt: str | None
    content: str
    author_id: int
    author: Author | None
    tags: list[Tag]
    published: bool
    published_at: str | None
    created_at: str
    updated_at: str


# ── Queries ───────────────────────────────────────────────────────────────────

@fraiseql.query(sql_source="v_post")
def posts(
    limit: int = 10,
    offset: int = 0,
    published: bool = True,
    author_id: int | None = None,
    tag_identifier: str | None = None,
) -> list[Post]:
    """List posts with pagination and filtering."""
    pass


@fraiseql.query(sql_source="v_post")
def post(id: int) -> Post | None:
    """Get a single post by ID."""
    pass


@fraiseql.query(sql_source="v_post")
def post_by_identifier(identifier: str) -> Post | None:
    """Get a single post by identifier."""
    pass


@fraiseql.query(sql_source="v_post_search")
def search_posts(query: str, limit: int = 10, offset: int = 0) -> list[Post]:
    """Full-text search across post titles and content.

    Note: tags are not populated in search results for performance. Fetch the
    full post via post(id) if tags are needed.
    """
    pass


@fraiseql.query(sql_source="v_author")
def authors(limit: int = 20, offset: int = 0) -> list[Author]:
    """List all authors."""
    pass


@fraiseql.query(sql_source="v_author")
def author(id: int) -> Author | None:
    """Get a single author by ID."""
    pass


@fraiseql.query(sql_source="v_tag")
def tags() -> list[Tag]:
    """List all tags."""
    pass


# ── Mutations ─────────────────────────────────────────────────────────────────

@fraiseql.mutation(sql_source="fn_create_post", operation="CREATE")
def create_post(
    title: str,
    content: str,
    author_id: int,
    excerpt: str | None = None,
    published: bool = False,
) -> Post:
    """Create a new blog post."""
    pass


@fraiseql.mutation(sql_source="fn_update_post", operation="UPDATE")
def update_post(
    id: int,
    title: str | None = None,
    content: str | None = None,
    excerpt: str | None = None,
    published: bool | None = None,
) -> Post:
    """Update an existing post."""
    pass


@fraiseql.mutation(sql_source="fn_add_tag_to_post", operation="CREATE")
def add_tag_to_post(post_id: int, tag_identifier: str) -> Post:
    """Add a tag to a post (creates tag if needed)."""
    pass


if __name__ == "__main__":
    fraiseql.export_schema("schema.json")
    print("schema.json generated — run: fraiseql compile && fraiseql run")
