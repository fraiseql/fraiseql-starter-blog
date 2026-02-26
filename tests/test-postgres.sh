#!/usr/bin/env bash
set -euo pipefail

PSQL="psql -h localhost -U postgres -d blog --no-psqlrc -v ON_ERROR_STOP=1"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1" >&2; exit 1; }

check_count() {
    local label="$1"
    local query="$2"
    local min="$3"
    local count
    count=$($PSQL -tAc "$query")
    if [ "$count" -ge "$min" ]; then
        pass "$label (count=$count)"
    else
        fail "$label: expected >= $min, got $count"
    fi
}

check_exists() {
    local label="$1"
    local query="$2"
    local count
    count=$($PSQL -tAc "$query")
    if [ "$count" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: not found"
    fi
}

echo "── Tables ──────────────────────────────────────────────────────────────"
for tbl in tb_author tb_tag tb_post tb_post_tag; do
    check_exists "table $tbl" \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='$tbl'"
done

echo "── Views ───────────────────────────────────────────────────────────────"
for view in v_author v_tag v_post v_post_search; do
    check_exists "view $view" \
        "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='public' AND table_name='$view'"
done

echo "── Functions ───────────────────────────────────────────────────────────"
for fn in fn_create_post fn_update_post fn_add_tag_to_post; do
    check_exists "function $fn" \
        "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='public' AND routine_name='$fn'"
done

echo "── GIN index ───────────────────────────────────────────────────────────"
check_exists "index tb_post_search_idx" \
    "SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public' AND tablename='tb_post' AND indexname='tb_post_search_idx'"

echo "── Seed counts ─────────────────────────────────────────────────────────"
check_count "tb_author seed" "SELECT COUNT(*) FROM tb_author" 2
check_count "tb_tag seed"    "SELECT COUNT(*) FROM tb_tag"    3
check_count "tb_post seed"   "SELECT COUNT(*) FROM tb_post"   2

echo "── v_post columns ──────────────────────────────────────────────────────"
expected_cols="id title identifier excerpt content author_id author tags published published_at created_at updated_at"
actual_cols=$($PSQL -tAc \
    "SELECT string_agg(column_name, ' ' ORDER BY ordinal_position)
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='v_post'")
for col in $expected_cols; do
    if echo "$actual_cols" | grep -qw "$col"; then
        pass "v_post column: $col"
    else
        fail "v_post missing column: $col"
    fi
done

echo "── fn_create_post ──────────────────────────────────────────────────────"
new_id=$($PSQL -tAc \
    "SELECT id FROM fn_create_post(
        'CI Test Post',
        'Content for CI test.',
        1,
        'CI excerpt',
        true
    ) LIMIT 1")
new_id=$(echo "$new_id" | tr -d '[:space:]')
if [ -z "$new_id" ]; then
    fail "fn_create_post returned no row"
fi
check_exists "fn_create_post result in v_post" \
    "SELECT COUNT(*) FROM v_post WHERE id = $new_id"

echo "── fn_add_tag_to_post ──────────────────────────────────────────────────"
$PSQL -c "SELECT fn_add_tag_to_post($new_id, 'ci-test')" > /dev/null
check_exists "ci-test tag in tb_tag" \
    "SELECT COUNT(*) FROM tb_tag WHERE identifier = 'ci-test'"

echo "── fn_update_post ──────────────────────────────────────────────────────"
updated_title=$($PSQL -tAc \
    "SELECT title FROM fn_update_post($new_id, p_title := 'CI Test Post Updated') LIMIT 1")
updated_title=$(echo "$updated_title" | tr -d '[:space:]')
if [ "$updated_title" = "CITestPostUpdated" ]; then
    pass "fn_update_post title updated correctly"
else
    fail "fn_update_post: expected 'CITestPostUpdated', got: '$updated_title'"
fi

echo "── Full-text search ────────────────────────────────────────────────────"
check_count "v_post_search FTS for 'FraiseQL'" \
    "SELECT COUNT(*) FROM v_post_search WHERE search_tsv @@ plainto_tsquery('english', 'FraiseQL')" 1

echo "── Cleanup ─────────────────────────────────────────────────────────────"
$PSQL -c "DELETE FROM tb_post_tag WHERE post_id = $new_id"
$PSQL -c "DELETE FROM tb_post     WHERE id = $new_id"
$PSQL -c "DELETE FROM tb_tag      WHERE identifier = 'ci-test'"
pass "cleanup done"

echo ""
echo "All PostgreSQL integration tests passed."
