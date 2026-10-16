package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type AuditRepository struct {
	q Querier
}

var _ repository.AuditRepository = (*AuditRepository)(nil)

func NewAuditRepository(q Querier) *AuditRepository {
	return &AuditRepository{q: q}
}

// History returns the change history of a row from v_change_history (the audit log written by triggers).
func (r *AuditRepository) History(ctx context.Context, tableName string, recordID int64) ([]domain.ChangeRecord, error) {
	rows, err := r.q.Query(ctx,
		`SELECT id, changed_at, table_name, record_id, operation, changed_fields, changed_by, changed_by_name,
		        old_data, new_data
		   FROM v_change_history
		  WHERE table_name = $1 AND record_id = $2
		  ORDER BY changed_at, id`, tableName, recordID)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, func(row pgx.Row) (domain.ChangeRecord, error) {
		var c domain.ChangeRecord
		err := row.Scan(&c.ID, &c.ChangedAt, &c.TableName, &c.RecordID, &c.Operation, &c.ChangedFields,
			&c.ChangedBy, &c.ChangedByName, &c.OldData, &c.NewData)
		return c, err
	})
}
