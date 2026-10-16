package postgres

import (
	"context"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"

	"university/internal/domain"
	"university/internal/repository"
)

type StudentRepository struct {
	q Querier
}

var _ repository.StudentRepository = (*StudentRepository)(nil)

func NewStudentRepository(q Querier) *StudentRepository {
	return &StudentRepository{q: q}
}

const studentColumns = `
	id, record_book_no, last_name, first_name, middle_name, full_name, birth_date,
	email, phone, enrollment_date, status, funding, group_id, group_code, study_year,
	specialty_id, specialty, faculty_id, faculty, curator, created_at, updated_at, updated_by_name`

func scanStudent(row pgx.Row) (domain.Student, error) {
	var s domain.Student
	err := row.Scan(
		&s.ID, &s.RecordBookNo, &s.LastName, &s.FirstName, &s.MiddleName, &s.FullName, &s.BirthDate,
		&s.Email, &s.Phone, &s.EnrollmentDate, &s.Status, &s.Funding, &s.GroupID, &s.GroupCode, &s.StudyYear,
		&s.SpecialtyID, &s.Specialty, &s.FacultyID, &s.Faculty, &s.Curator, &s.CreatedAt, &s.UpdatedAt, &s.UpdatedByName,
	)
	return s, err
}

// GetByID reads a student from v_students (soft-deleted students are not returned).
func (r *StudentRepository) GetByID(ctx context.Context, id int64) (*domain.Student, error) {
	s, err := scanStudent(r.q.QueryRow(ctx, `SELECT `+studentColumns+` FROM v_students WHERE id = $1`, id))
	if err != nil {
		return nil, MapError(err)
	}
	return &s, nil
}

func (r *StudentRepository) List(ctx context.Context, f domain.StudentFilter) ([]domain.Student, error) {
	var (
		where []string
		args  []any
	)
	if f.GroupID != nil {
		args = append(args, *f.GroupID)
		where = append(where, "group_id = $"+strconv.Itoa(len(args)))
	}
	if f.Status != nil {
		args = append(args, string(*f.Status))
		where = append(where, "status = $"+strconv.Itoa(len(args))+"::student_status")
	}

	sql := `SELECT ` + studentColumns + ` FROM v_students`
	if len(where) > 0 {
		sql += " WHERE " + strings.Join(where, " AND ")
	}
	sql += " ORDER BY group_code, full_name"
	if f.Limit > 0 {
		args = append(args, f.Limit)
		sql += " LIMIT $" + strconv.Itoa(len(args))
	}
	if f.Offset > 0 {
		args = append(args, f.Offset)
		sql += " OFFSET $" + strconv.Itoa(len(args))
	}

	rows, err := r.q.Query(ctx, sql, args...)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, scanStudent)
}

// Search is a fuzzy search by full name with the fn_search_students table function (GIN pg_trgm).
func (r *StudentRepository) Search(ctx context.Context, query string, limit int) ([]domain.StudentSearchResult, error) {
	rows, err := r.q.Query(ctx,
		`SELECT student_id, full_name, group_code, record_book_no, similarity
		   FROM fn_search_students($1, $2)`, query, limit)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, func(row pgx.Row) (domain.StudentSearchResult, error) {
		var s domain.StudentSearchResult
		err := row.Scan(&s.StudentID, &s.FullName, &s.GroupCode, &s.RecordBookNo, &s.Similarity)
		return s, err
	})
}

func (r *StudentRepository) ListDeleted(ctx context.Context) ([]domain.DeletedStudent, error) {
	rows, err := r.q.Query(ctx,
		`SELECT id, record_book_no, full_name, group_code, status, deleted_at, deleted_by, deleted_by_name
		   FROM v_students_deleted
		  ORDER BY deleted_at DESC`)
	if err != nil {
		return nil, MapError(err)
	}
	return collect(rows, func(row pgx.Row) (domain.DeletedStudent, error) {
		var d domain.DeletedStudent
		err := row.Scan(&d.ID, &d.RecordBookNo, &d.FullName, &d.GroupCode, &d.Status,
			&d.DeletedAt, &d.DeletedBy, &d.DeletedByName)
		return d, err
	})
}

// Create calls sp_student_create; the INOUT parameter returns the new student id.
func (r *StudentRepository) Create(ctx context.Context, s domain.NewStudent) (int64, error) {
	var id int64
	err := r.q.QueryRow(ctx,
		`CALL sp_student_create($1, $2, $3, $4, $5, $6, $7, $8, $9::funding_type, NULL::bigint)`,
		s.GroupID, s.RecordBookNo, s.LastName, s.FirstName, optional(s.MiddleName), s.BirthDate,
		optional(s.Email), optional(s.Phone), string(s.Funding),
	).Scan(&id)
	return id, MapError(err)
}

func (r *StudentRepository) Update(ctx context.Context, id int64, u domain.StudentUpdate) error {
	_, err := r.q.Exec(ctx,
		`CALL sp_student_update($1, $2, $3, $4, $5, $6, $7, $8::funding_type)`,
		id, u.LastName, u.FirstName, optional(u.MiddleName), u.BirthDate,
		optional(u.Email), optional(u.Phone), string(u.Funding))
	return MapError(err)
}

func (r *StudentRepository) SetStatus(ctx context.Context, id int64, status domain.StudentStatus) error {
	_, err := r.q.Exec(ctx, `CALL sp_student_set_status($1, $2::student_status)`, id, string(status))
	return MapError(err)
}

func (r *StudentRepository) Transfer(ctx context.Context, id, toGroupID int64, reason string) (int64, error) {
	var transferID int64
	err := r.q.QueryRow(ctx, `CALL sp_student_transfer($1, $2, $3, NULL::bigint)`, id, toGroupID, reason).
		Scan(&transferID)
	return transferID, MapError(err)
}

func (r *StudentRepository) SoftDelete(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_student_soft_delete($1)`, id)
	return MapError(err)
}

func (r *StudentRepository) Restore(ctx context.Context, id int64) error {
	_, err := r.q.Exec(ctx, `CALL sp_student_restore($1)`, id)
	return MapError(err)
}
