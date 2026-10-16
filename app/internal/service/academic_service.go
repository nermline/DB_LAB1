// Package service contains the academic scenarios. Each scenario changes
// several related entities (student, course enrollments, grades) and runs
// as one unit of work.
package service

import (
	"context"
	"fmt"

	"university/internal/domain"
	"university/internal/uow"
)

type AcademicService struct {
	uow uow.Factory
}

func NewAcademicService(f uow.Factory) *AcademicService {
	return &AcademicService{uow: f}
}

// Admission is the result of admitting a student.
type Admission struct {
	Student     *domain.Student
	Semester    *domain.Semester
	Enrollments []domain.Enrollment
}

// AdmitStudent admits a student to a group and enrolls them in the current
// semester courses of the curriculum. If any step fails, nothing is saved:
// neither the student nor the enrollments.
func (s *AcademicService) AdmitStudent(ctx context.Context, actorID int64, groupCode string, ns domain.NewStudent) (*Admission, error) {
	var res Admission
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		group, err := u.Groups().GetByCode(ctx, groupCode)
		if err != nil {
			return fmt.Errorf("group %q: %w", groupCode, err)
		}
		semester, err := u.Catalog().CurrentSemester(ctx)
		if err != nil {
			return fmt.Errorf("current semester: %w", err)
		}

		ns.GroupID = group.ID
		studentID, err := u.Students().Create(ctx, ns)
		if err != nil {
			return fmt.Errorf("create student: %w", err)
		}
		if _, err := u.Enrollments().EnrollByCurriculum(ctx, studentID, semester.ID); err != nil {
			return fmt.Errorf("enroll in courses: %w", err)
		}

		if res.Student, err = u.Students().GetByID(ctx, studentID); err != nil {
			return err
		}
		res.Semester = semester
		res.Enrollments, err = u.Enrollments().ListByStudent(ctx, studentID, &semester.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return &res, nil
}

// RecordGrades adds a batch of grades atomically: all of them or none.
// It returns the updated enrollments with the new total score.
func (s *AcademicService) RecordGrades(ctx context.Context, actorID int64, grades []domain.NewGrade) ([]domain.Enrollment, error) {
	var result []domain.Enrollment
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		var touched []int64
		seen := make(map[int64]bool)
		for i, g := range grades {
			if _, err := u.Grades().Add(ctx, g); err != nil {
				return fmt.Errorf("grade %d (%s): %w", i+1, g.Title, err)
			}
			if !seen[g.EnrollmentID] {
				seen[g.EnrollmentID] = true
				touched = append(touched, g.EnrollmentID)
			}
		}
		for _, id := range touched {
			e, err := u.Enrollments().GetByID(ctx, id)
			if err != nil {
				return err
			}
			result = append(result, *e)
		}
		return nil
	})
	return result, err
}

// CorrectGrade changes an assessment score (recorded in the audit log).
func (s *AcademicService) CorrectGrade(ctx context.Context, actorID, gradeID int64, score float64, comment string) (*domain.Grade, error) {
	var grade *domain.Grade
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		if err := u.Grades().Update(ctx, gradeID, score, comment); err != nil {
			return err
		}
		var err error
		grade, err = u.Grades().GetByID(ctx, gradeID)
		return err
	})
	return grade, err
}

// FinalizeEnrollment sets the final course grade.
func (s *AcademicService) FinalizeEnrollment(ctx context.Context, actorID, enrollmentID int64) (*domain.Enrollment, error) {
	var e *domain.Enrollment
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		if err := u.Enrollments().Finalize(ctx, enrollmentID); err != nil {
			return err
		}
		var err error
		e, err = u.Enrollments().GetByID(ctx, enrollmentID)
		return err
	})
	return e, err
}

// Transfer is the result of a student transfer.
type Transfer struct {
	TransferID     int64
	Student        *domain.Student
	NewEnrollments int
}

// TransferStudent moves a student to another group and enrolls them in the
// curriculum courses of the new group for the current semester.
func (s *AcademicService) TransferStudent(ctx context.Context, actorID, studentID int64, toGroupCode, reason string) (*Transfer, error) {
	var res Transfer
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		group, err := u.Groups().GetByCode(ctx, toGroupCode)
		if err != nil {
			return fmt.Errorf("group %q: %w", toGroupCode, err)
		}
		semester, err := u.Catalog().CurrentSemester(ctx)
		if err != nil {
			return err
		}
		if res.TransferID, err = u.Students().Transfer(ctx, studentID, group.ID, reason); err != nil {
			return err
		}
		if res.NewEnrollments, err = u.Enrollments().EnrollByCurriculum(ctx, studentID, semester.ID); err != nil {
			return err
		}
		res.Student, err = u.Students().GetByID(ctx, studentID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return &res, nil
}

// ExpelStudent expels a student. A database trigger sets their active
// enrollments to dropped; they are returned to show the effect.
func (s *AcademicService) ExpelStudent(ctx context.Context, actorID, studentID int64) ([]domain.Enrollment, error) {
	var enrollments []domain.Enrollment
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		if err := u.Students().SetStatus(ctx, studentID, domain.StudentExpelled); err != nil {
			return err
		}
		semester, err := u.Catalog().CurrentSemester(ctx)
		if err != nil {
			return err
		}
		enrollments, err = u.Enrollments().ListByStudent(ctx, studentID, &semester.ID)
		return err
	})
	return enrollments, err
}

// RemoveStudent soft-deletes a student (the row stays in the database with deleted_at / deleted_by).
func (s *AcademicService) RemoveStudent(ctx context.Context, actorID, studentID int64) error {
	return s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		return u.Students().SoftDelete(ctx, studentID)
	})
}

// RestoreStudent restores a soft-deleted student.
func (s *AcademicService) RestoreStudent(ctx context.Context, actorID, studentID int64) (*domain.Student, error) {
	var st *domain.Student
	err := s.uow.Do(ctx, actorID, func(u uow.UnitOfWork) error {
		if err := u.Students().Restore(ctx, studentID); err != nil {
			return err
		}
		var err error
		st, err = u.Students().GetByID(ctx, studentID)
		return err
	})
	return st, err
}

// StudentCard is a summary of a student.
type StudentCard struct {
	Student     *domain.Student
	Results     []domain.SemesterResult
	Enrollments []domain.Enrollment
	Grades      map[int64][]domain.Grade // enrollment_id -> grades
}

// GetStudentCard reads the student card in one read-only transaction
// (a consistent snapshot of several views).
func (s *AcademicService) GetStudentCard(ctx context.Context, studentID int64) (*StudentCard, error) {
	card := StudentCard{Grades: make(map[int64][]domain.Grade)}
	err := s.uow.Read(ctx, func(u uow.UnitOfWork) error {
		var err error
		if card.Student, err = u.Students().GetByID(ctx, studentID); err != nil {
			return err
		}
		if card.Results, err = u.Enrollments().SemesterResults(ctx, studentID); err != nil {
			return err
		}
		if card.Enrollments, err = u.Enrollments().ListByStudent(ctx, studentID, nil); err != nil {
			return err
		}
		for _, e := range card.Enrollments {
			if card.Grades[e.ID], err = u.Grades().ListByEnrollment(ctx, e.ID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &card, nil
}

// GroupRating returns the group ranking for a semester.
func (s *AcademicService) GroupRating(ctx context.Context, groupCode string, semesterID int64) ([]domain.RatingEntry, error) {
	var rating []domain.RatingEntry
	err := s.uow.Read(ctx, func(u uow.UnitOfWork) error {
		group, err := u.Groups().GetByCode(ctx, groupCode)
		if err != nil {
			return fmt.Errorf("group %q: %w", groupCode, err)
		}
		rating, err = u.Groups().Rating(ctx, group.ID, semesterID)
		return err
	})
	return rating, err
}

// StudentHistory returns the change history of a student from the audit log.
func (s *AcademicService) StudentHistory(ctx context.Context, studentID int64) ([]domain.ChangeRecord, error) {
	var history []domain.ChangeRecord
	err := s.uow.Read(ctx, func(u uow.UnitOfWork) error {
		var err error
		history, err = u.Audit().History(ctx, "students", studentID)
		return err
	})
	return history, err
}
