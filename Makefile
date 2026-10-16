PGURL     ?= postgres://postgres:postgres@localhost:5432
DB_NAME   ?= university
DB_URL    := $(PGURL)/$(DB_NAME)?sslmode=disable
SQL_FILES := $(sort $(wildcard sql/0*.sql))

.PHONY: up down db-reset demo-sql demo test

up:
	docker compose up -d --wait

down:
	docker compose down -v

db-reset:
	psql -X "$(PGURL)/postgres" -c "DROP DATABASE IF EXISTS $(DB_NAME) WITH (FORCE)" -c "CREATE DATABASE $(DB_NAME)"
	@for f in $(SQL_FILES); do echo "→ $$f"; psql -X -q -v ON_ERROR_STOP=1 "$(DB_URL)" -f $$f > /dev/null || exit 1; done

demo-sql:
	psql -X "$(DB_URL)" -f sql/demo/demo_queries.sql

demo:
	cd app && go run ./cmd/demo -dsn "$(DB_URL)"

test:
	cd app && UNIVERSITY_TEST_DSN="$(DB_URL)" go test ./... -count=1
