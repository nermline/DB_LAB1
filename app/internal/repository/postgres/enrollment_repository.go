package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type EnrollmentRepository struct {
	q Querier
}

var _ repository.EnrollmentRepository = (*EnrollmentRepository)(nil)

func NewEnrollmentRepository(q Querier) *EnrollmentRepository {
	return &EnrollmentRepository{q: q}
}

const enrollmentColumns = `
	id, student_id, student_name, group_code, course_id, course_code, course_name, credits, control,
	semester_id, semester, status, score, ects_grade, national_grade, enrolled_at, finalized_at, updated_at`

func scanEnrollment(row pgx.Row) (domain.Enrollment, error) {
	var e domain.Enrollment
	err := row.Scan(&e.ID, &e.StudentID, &e.StudentName, &e.GroupCode, &e.CourseID, &e.CourseCode, &e.CourseName,
		&e.Credits, &e.Control, &e.SemesterID, &e.Semester, &e.Status, &e.Score, &e.ECTSGrade, &e.NationalGrade,
		&e.EnrolledAt, &e.FinalizedAt, &e.UpdatedAt)
	return e, err
}

func (r *EnrollmentRepository) GetByID(ctx context.Context, id int64) (*domain.Enrollment, error) {
	e, err := scanEnrollment(r.q.QueryRow(ctx, `SELECT `+enrollmentColumns+` FROM v_enrollments WHERE id = $1`, id))
	if err != nil {
		return nil, MapError(err)
	}
	return &e, nil
}

// ListByStudent returns the enrollments of a student; semesterID == nil means all semesters.
func (r *EnrollmentRepository) ListByStudent(ctx context.Context, studentID int64, semesterID *int64) ([]domain.Enrollment, error) {
	rows, err := r.q.Query(ctx,
		`SELECT `+enrollmentColumns+`
		   FROM v_enrollments
		  WHERE student_id = $1
		    AND ($2::bigint IS NULL OR semester_id = $2)
		  ORDER BY semester_id, course_code`, studentID, semesterID)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, scanEnrollment)
}

func (r *EnrollmentRepository) SemesterResults(ctx context.Context, studentID int64) ([]domain.SemesterResult, error) {
	rows, err := r.q.Query(ctx,
		`SELECT student_id, full_name, group_code, semester_id, semester, courses_total, courses_passed,
		        debts, credits_total, credits_earned, rating
		   FROM v_student_semester_results
		  WHERE student_id = $1
		  ORDER BY semester_id`, studentID)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, func(row pgx.Row) (domain.SemesterResult, error) {
		var s domain.SemesterResult
		err := row.Scan(&s.StudentID, &s.FullName, &s.GroupCode, &s.SemesterID, &s.Semester, &s.CoursesTotal,
			&s.CoursesPassed, &s.Debts, &s.CreditsTotal, &s.CreditsEarned, &s.Rating)
		return s, err
	})
}

func (r *EnrollmentRepository) Create(ctx context.Context, studentID, courseID, semesterID int64) (int64, error) {
	var id int64
	err := r.q.QueryRow(ctx, `CALL sp_enrollment_create($1, $2, $3, NULL::bigint)`,
		studentID, courseID, semesterID).Scan(&id)
	return id, MapError(err)
}

// EnrollByCurriculum enrolls a student in all curriculum courses of their group for a semester.
func (r *EnrollmentRepository) EnrollByCurriculum(ctx context.Context, studentID, semesterID int64) (int, error) {
	var enrolled int
	err := r.q.QueryRow(ctx, `CALL sp_enroll_student_by_curriculum($1, $2, NULL::integer)`,
		studentID, semesterID).Scan(&enrolled)
	return enrolled, MapError(err)
}

func (r *EnrollmentRepository) Drop(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_enrollment_drop($1)`, id)
	return MapError(err)
}

// Finalize sets the final grade: total score, ECTS grade and national scale grade.
func (r *EnrollmentRepository) Finalize(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_enrollment_finalize($1)`, id)
	return MapError(err)
}
