package domain

import "errors"

// Error categories that repositories map SQLSTATE codes to
// (returned by stored procedures and triggers).
var (
	ErrNotFound     = errors.New("not found")                  // P0002 no_data_found
	ErrBusinessRule = errors.New("business rule violation")    // UA001, 23514 check_violation
	ErrConflict     = errors.New("data conflict")              // 23505 unique_violation, 23P01 exclusion_violation
	ErrReference    = errors.New("reference to a missing row") // 23503 foreign_key_violation
	ErrForbidden    = errors.New("access denied")              // 42501 insufficient_privilege
)
