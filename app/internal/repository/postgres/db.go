// Package postgres implements the repositories on top of PostgreSQL (pgx v5).
// All queries are SELECTs from views (v_*) / table functions (fn_*)
// or CALLs of stored procedures (sp_*).
package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"university/internal/domain"
)

// Querier is the common interface of pgx.Tx, *pgxpool.Pool and *pgx.Conn.
// Repositories receive the transaction from the Unit of Work, so all of them
// work in one transaction with one user context.
type Querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// MapError converts PostgreSQL errors (SQLSTATE) to domain errors,
// keeping the message from the procedure / trigger.
func MapError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrNotFound
	}

	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return err
	}

	var kind error
	switch pgErr.Code {
	case "P0002": // no_data_found
		kind = domain.ErrNotFound
	case "UA001", "23514": // custom business rule, check_violation
		kind = domain.ErrBusinessRule
	case "23505", "23P01": // unique_violation, exclusion_violation
		kind = domain.ErrConflict
	case "23503": // foreign_key_violation
		kind = domain.ErrReference
	case "42501": // insufficient_privilege
		kind = domain.ErrForbidden
	default:
		return err
	}
	return fmt.Errorf("%w: %s", kind, pgErr.Message)
}

// optional converts an empty string to NULL.
func optional(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// collect reads all result rows using the scan function.
func collect[T any](rows pgx.Rows, scan func(pgx.Row) (T, error)) ([]T, error) {
	defer rows.Close()
	var result []T
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			return nil, MapError(err)
		}
		result = append(result, item)
	}
	return result, MapError(rows.Err())
}
