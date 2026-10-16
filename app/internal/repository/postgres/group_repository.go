package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type GroupRepository struct {
	q Querier
}

var _ repository.GroupRepository = (*GroupRepository)(nil)

func NewGroupRepository(q Querier) *GroupRepository {
	return &GroupRepository{q: q}
}

const groupColumns = `
	id, code, admission_year, study_year, max_size, specialty_id, specialty, degree_level,
	faculty, curator, active_students, budget_students, on_leave`

func scanGroup(row pgx.Row) (domain.Group, error) {
	var g domain.Group
	err := row.Scan(&g.ID, &g.Code, &g.AdmissionYear, &g.StudyYear, &g.MaxSize, &g.SpecialtyID, &g.Specialty,
		&g.DegreeLevel, &g.Faculty, &g.Curator, &g.ActiveStudents, &g.BudgetStudents, &g.OnLeave)
	return g, err
}

func (r *GroupRepository) GetByID(ctx context.Context, id int64) (*domain.Group, error) {
	g, err := scanGroup(r.q.QueryRow(ctx, `SELECT `+groupColumns+` FROM v_groups WHERE id = $1`, id))
	if err != nil {
		return nil, MapError(err)
	}
	return &g, nil
}

func (r *GroupRepository) GetByCode(ctx context.Context, code string) (*domain.Group, error) {
	g, err := scanGroup(r.q.QueryRow(ctx, `SELECT `+groupColumns+` FROM v_groups WHERE code = $1`, code))
	if err != nil {
		return nil, MapError(err)
	}
	return &g, nil
}

func (r *GroupRepository) List(ctx context.Context) ([]domain.Group, error) {
	rows, err := r.q.Query(ctx, `SELECT `+groupColumns+` FROM v_groups ORDER BY code`)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, scanGroup)
}

// Rating returns the group ranking for a semester (table function fn_group_rating with the RANK() window function).
func (r *GroupRepository) Rating(ctx context.Context, groupID, semesterID int64) ([]domain.RatingEntry, error) {
	rows, err := r.q.Query(ctx,
		`SELECT place, student_id, full_name, funding, rating, credits, debts
		   FROM fn_group_rating($1, $2)`, groupID, semesterID)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, func(row pgx.Row) (domain.RatingEntry, error) {
		var e domain.RatingEntry
		err := row.Scan(&e.Place, &e.StudentID, &e.FullName, &e.Funding, &e.Rating, &e.Credits, &e.Debts)
		return e, err
	})
}
