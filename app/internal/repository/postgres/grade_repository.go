package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type GradeRepository struct {
	q Querier
}

var _ repository.GradeRepository = (*GradeRepository)(nil)

func NewGradeRepository(q Querier) *GradeRepository {
	return &GradeRepository{q: q}
}

const gradeColumns = `
	id, enrollment_id, student_id, student_name, course_name, semester_id, assessment_type, title,
	score, max_score, graded_on, teacher_id, teacher_name, comment, updated_at, updated_by_name`

func scanGrade(row pgx.Row) (domain.Grade, error) {
	var g domain.Grade
	err := row.Scan(&g.ID, &g.EnrollmentID, &g.StudentID, &g.StudentName, &g.CourseName, &g.SemesterID, &g.Type,
		&g.Title, &g.Score, &g.MaxScore, &g.GradedOn, &g.TeacherID, &g.TeacherName, &g.Comment, &g.UpdatedAt,
		&g.UpdatedByName)
	return g, err
}

func (r *GradeRepository) GetByID(ctx context.Context, id int64) (*domain.Grade, error) {
	g, err := scanGrade(r.q.QueryRow(ctx, `SELECT `+gradeColumns+` FROM v_grades WHERE id = $1`, id))
	if err != nil {
		return nil, MapError(err)
	}
	return &g, nil
}

func (r *GradeRepository) ListByEnrollment(ctx context.Context, enrollmentID int64) ([]domain.Grade, error) {
	rows, err := r.q.Query(ctx,
		`SELECT `+gradeColumns+` FROM v_grades WHERE enrollment_id = $1 ORDER BY graded_on, id`, enrollmentID)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, scanGrade)
}

// Add adds a grade with sp_grade_add. The trg_20_validate trigger checks
// that the enrollment is not finalized and the total score does not exceed 100.
func (r *GradeRepository) Add(ctx context.Context, g domain.NewGrade) (int64, error) {
	var id int64
	err := r.q.QueryRow(ctx,
		`CALL sp_grade_add($1, $2::assessment_type, $3, $4, $5, $6, $7, NULL::bigint)`,
		g.EnrollmentID, string(g.Type), g.Title, g.Score, g.MaxScore, g.TeacherID, g.Comment,
	).Scan(&id)
	return id, MapError(err)
}

func (r *GradeRepository) Update(ctx context.Context, id int64, score float64, comment string) error {
	_, err := r.q.Exec(ctx, `CALL sp_grade_update($1, $2, $3)`, id, score, comment)
	return MapError(err)
}

func (r *GradeRepository) SoftDelete(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_grade_soft_delete($1)`, id)
	return MapError(err)
}

func (r *GradeRepository) Restore(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_grade_restore($1)`, id)
	return MapError(err)
}
