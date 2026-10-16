// Package uow implements the Unit of Work pattern on top of a PostgreSQL transaction.
//
// One unit of work = one database transaction. All repositories obtained from
// a UnitOfWork run their queries in this transaction, so changes to several
// related entities (student -> course enrollments -> grades) are committed
// together (Commit) or fully discarded (Rollback).
//
// At the start of the transaction fn_set_current_user(actorID) is called:
// the database triggers take updated_by / deleted_by and the audit log
// changed_by from it.
package uow

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"university/internal/repository"
	"university/internal/repository/postgres"
)

// UnitOfWork is a set of repositories that work in one transaction.
type UnitOfWork interface {
	Students() repository.StudentRepository
	Groups() repository.GroupRepository
	Catalog() repository.CatalogRepository
	Enrollments() repository.EnrollmentRepository
	Grades() repository.GradeRepository
	Audit() repository.AuditRepository

	Commit(ctx context.Context) error
	Rollback(ctx context.Context) error
}

// Factory creates units of work.
type Factory interface {
	// Begin opens a transaction on behalf of user actorID.
	// Commit or Rollback must be called when the work is done.
	Begin(ctx context.Context, actorID int64) (UnitOfWork, error)

	// Do runs fn in one transaction: Commit if fn returns nil,
	// otherwise (or on panic) Rollback.
	Do(ctx context.Context, actorID int64, fn func(UnitOfWork) error) error

	// Read runs fn in a read-only transaction.
	Read(ctx context.Context, fn func(UnitOfWork) error) error
}

// PostgresFactory is a Factory implementation based on a pgx connection pool.
type PostgresFactory struct {
	pool *pgxpool.Pool
}

var _ Factory = (*PostgresFactory)(nil)

func NewPostgresFactory(pool *pgxpool.Pool) *PostgresFactory {
	return &PostgresFactory{pool: pool}
}

func (f *PostgresFactory) Begin(ctx context.Context, actorID int64) (UnitOfWork, error) {
	return f.begin(ctx, actorID, pgx.TxOptions{IsoLevel: pgx.ReadCommitted, AccessMode: pgx.ReadWrite})
}

func (f *PostgresFactory) Do(ctx context.Context, actorID int64, fn func(UnitOfWork) error) error {
	u, err := f.Begin(ctx, actorID)
	if err != nil {
		return err
	}
	return run(ctx, u, fn)
}

func (f *PostgresFactory) Read(ctx context.Context, fn func(UnitOfWork) error) error {
	u, err := f.begin(ctx, 0, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return err
	}
	return run(ctx, u, fn)
}

func (f *PostgresFactory) begin(ctx context.Context, actorID int64, opts pgx.TxOptions) (UnitOfWork, error) {
	tx, err := f.pool.BeginTx(ctx, opts)
	if err != nil {
		return nil, fmt.Errorf("begin transaction: %w", err)
	}
	if actorID > 0 {
		// the value lives only until the end of this transaction (set_config(..., is_local = true))
		if _, err := tx.Exec(ctx, `SELECT fn_set_current_user($1)`, actorID); err != nil {
			_ = tx.Rollback(ctx)
			return nil, postgres.MapError(err)
		}
	}
	return newPostgresUnitOfWork(tx), nil
}

func run(ctx context.Context, u UnitOfWork, fn func(UnitOfWork) error) (err error) {
	defer func() {
		if p := recover(); p != nil {
			_ = u.Rollback(ctx)
			panic(p)
		}
	}()

	if err := fn(u); err != nil {
		if rbErr := u.Rollback(ctx); rbErr != nil {
			return errors.Join(err, fmt.Errorf("rollback: %w", rbErr))
		}
		return err
	}
	return u.Commit(ctx)
}

// postgresUnitOfWork holds repositories that share one pgx.Tx.
type postgresUnitOfWork struct {
	tx          pgx.Tx
	students    *postgres.StudentRepository
	groups      *postgres.GroupRepository
	catalog     *postgres.CatalogRepository
	enrollments *postgres.EnrollmentRepository
	grades      *postgres.GradeRepository
	audit       *postgres.AuditRepository
}

func newPostgresUnitOfWork(tx pgx.Tx) *postgresUnitOfWork {
	return &postgresUnitOfWork{
		tx:          tx,
		students:    postgres.NewStudentRepository(tx),
		groups:      postgres.NewGroupRepository(tx),
		catalog:     postgres.NewCatalogRepository(tx),
		enrollments: postgres.NewEnrollmentRepository(tx),
		grades:      postgres.NewGradeRepository(tx),
		audit:       postgres.NewAuditRepository(tx),
	}
}

func (u *postgresUnitOfWork) Students() repository.StudentRepository       { return u.students }
func (u *postgresUnitOfWork) Groups() repository.GroupRepository           { return u.groups }
func (u *postgresUnitOfWork) Catalog() repository.CatalogRepository        { return u.catalog }
func (u *postgresUnitOfWork) Enrollments() repository.EnrollmentRepository { return u.enrollments }
func (u *postgresUnitOfWork) Grades() repository.GradeRepository           { return u.grades }
func (u *postgresUnitOfWork) Audit() repository.AuditRepository            { return u.audit }

func (u *postgresUnitOfWork) Commit(ctx context.Context) error {
	if err := u.tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", postgres.MapError(err))
	}
	return nil
}

// Rollback is safe to call again or after Commit.
func (u *postgresUnitOfWork) Rollback(ctx context.Context) error {
	if err := u.tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
		return err
	}
	return nil
}
