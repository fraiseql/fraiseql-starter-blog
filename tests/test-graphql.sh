#!/usr/bin/env bash
set -euo pipefail

GQL_URL="${GRAPHQL_URL:-http://localhost:8080/graphql}"

gql() {
    local label="$1"
    local query="$2"
    local response
    response=$(curl -sf -X POST "$GQL_URL" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg q "$query" '{"query": $q}')")
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "❌ $label" >&2
        echo "$response" | jq '.errors' >&2
        exit 1
    fi
    echo "✅ $label"
    echo "$response"
}

echo "── GraphQL smoke tests ─────────────────────────────────────────────────"

gql "posts query" '{ posts(limit: 5) { id title identifier author { name } tags { identifier label } } }' \
    | jq -e '.data.posts | length >= 1' > /dev/null

gql "authors query" '{ authors { id name email } }' \
    | jq -e '.data.authors | length >= 1' > /dev/null

gql "tags query" '{ tags { id identifier label } }' \
    | jq -e '.data.tags | length >= 1' > /dev/null

gql "searchPosts query" '{ searchPosts(query: "FraiseQL") { id title } }' \
    | jq -e '.data.searchPosts | length >= 1' > /dev/null

gql "post by id" '{ post(id: 1) { id title identifier } }' \
    | jq -e '.data.post.id == 1' > /dev/null

echo ""
echo "All GraphQL smoke tests passed."
