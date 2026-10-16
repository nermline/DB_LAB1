// Package repository defines the repository contracts.
//
// Every implementation must:
//   - read data ONLY from views or table functions;
//   - change data ONLY through stored procedures (CALL sp_...).
//
// The code never runs INSERT / UPDATE / DELETE on tables directly.
package repository

import (
	"context"

	"university/internal/domain"
)

// StudentRepository works with students (v_students, v_students_deleted, fn_search_students, sp_student_*).
type StudentRepository interface {
	GetByID(ctx context.Context, id int64) (*domain.Student, error)
	List(ctx context.Context, filter domain.StudentFilter) ([]domain.Student, error)
	Search(ctx context.Context, query string, limit int) ([]domain.StudentSearchResult, error)
	ListDeleted(ctx context.Context) ([]domain.DeletedStudent, error)

	Create(ctx context.Context, s domain.NewStudent) (int64, error)
	Update(ctx context.Context, id int64, u domain.StudentUpdate) error
	SetStatus(ctx context.Context, id int64, status domain.StudentStatus) error
	Transfer(ctx context.Context, id, toGroupID int64, reason string) (transferID int64, err error)
	SoftDelete(ctx context.Context, id int64) error
	Restore(ctx context.Context, id int64) error
}

// GroupRepository works with student groups (v_groups, fn_group_rating).
type GroupRepository interface {
	GetByID(ctx context.Context, id int64) (*domain.Group, error)
	GetByCode(ctx context.Context, code string) (*domain.Group, error)
	List(ctx context.Context) ([]domain.Group, error)
	Rating(ctx context.Context, groupID, semesterID int64) ([]domain.RatingEntry, error)
}

// CatalogRepository works with reference data: semesters and courses (v_semesters, v_courses).
type CatalogRepository interface {
	CurrentSemester(ctx context.Context) (*domain.Semester, error)
	Semesters(ctx context.Context) ([]domain.Semester, error)
	CourseByCode(ctx context.Context, code string) (*domain.Course, error)
}

// EnrollmentRepository works with course enrollments (v_enrollments, v_student_semester_results, sp_enrollment_*).
type EnrollmentRepository interface {
	GetByID(ctx context.Context, id int64) (*domain.Enrollment, error)
	ListByStudent(ctx context.Context, studentID int64, semesterID *int64) ([]domain.Enrollment, error)
	SemesterResults(ctx context.Context, studentID int64) ([]domain.SemesterResult, error)

	Create(ctx context.Context, studentID, courseID, semesterID int64) (int64, error)
	EnrollByCurriculum(ctx context.Context, studentID, semesterID int64) (enrolled int, err error)
	Drop(ctx context.Context, id int64) error
	Finalize(ctx context.Context, id int64) error
}

// GradeRepository works with grades (v_grades, sp_grade_*).
type GradeRepository interface {
	GetByID(ctx context.Context, id int64) (*domain.Grade, error)
	ListByEnrollment(ctx context.Context, enrollmentID int64) ([]domain.Grade, error)

	Add(ctx context.Context, g domain.NewGrade) (int64, error)
	Update(ctx context.Context, id int64, score float64, comment string) error
	SoftDelete(ctx context.Context, id int64) error
	Restore(ctx context.Context, id int64) error
}

// AuditRepository works with the change log (v_change_history).
type AuditRepository interface {
	History(ctx context.Context, tableName string, recordID int64) ([]domain.ChangeRecord, error)
}
