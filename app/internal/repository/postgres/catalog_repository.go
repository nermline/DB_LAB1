package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type CatalogRepository struct {
	q Querier
}

var _ repository.CatalogRepository = (*CatalogRepository)(nil)

func NewCatalogRepository(q Querier) *CatalogRepository {
	return &CatalogRepository{q: q}
}

const semesterColumns = `id, academic_year, term, name, start_date, end_date, is_current, is_closed`

func scanSemester(row pgx.Row) (domain.Semester, error) {
	var s domain.Semester
	err := row.Scan(&s.ID, &s.AcademicYear, &s.Term, &s.Name, &s.StartDate, &s.EndDate, &s.IsCurrent, &s.IsClosed)
	return s, err
}

func (r *CatalogRepository) CurrentSemester(ctx context.Context) (*domain.Semester, error) {
	s, err := scanSemester(r.q.QueryRow(ctx, `SELECT `+semesterColumns+` FROM v_semesters WHERE is_current`))
	if err != nil {
		return nil, MapError(err)
	}
	return &s, nil
}

func (r *CatalogRepository) Semesters(ctx context.Context) ([]domain.Semester, error) {
	rows, err := r.q.Query(ctx, `SELECT `+semesterColumns+` FROM v_semesters ORDER BY start_date`)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, scanSemester)
}

func (r *CatalogRepository) CourseByCode(ctx context.Context, code string) (*domain.Course, error) {
	var c domain.Course
	err := r.q.QueryRow(ctx,
		`SELECT id, code, name, credits, lecture_hours, practice_hours, lab_hours, control, department_id, department
		   FROM v_courses WHERE code = $1`, code,
	).Scan(&c.ID, &c.Code, &c.Name, &c.Credits, &c.LectureHours, &c.PracticeHours, &c.LabHours,
		&c.Control, &c.DepartmentID, &c.Department)
	if err != nil {
		return nil, MapError(err)
	}
	return &c, nil
}
