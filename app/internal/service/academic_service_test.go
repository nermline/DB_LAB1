package service_test

// Integration tests: they need a deployed database with the test data.
//
//	UNIVERSITY_TEST_DSN="postgres://postgres:postgres@localhost:5432/university?sslmode=disable" go test ./...

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"university/internal/domain"
	"university/internal/service"
	"university/internal/uow"
)

const (
	deanOfficeUser = 2 // Olena Koval (Dean Office), from 08_seed.sql
	registrarUser  = 3 // Ihor Danyliuk (Registrar)
	testGroup      = "AM-24"
)

func setup(t *testing.T) (*uow.PostgresFactory, *service.AcademicService) {
	t.Helper()
	dsn := os.Getenv("UNIVERSITY_TEST_DSN")
	if dsn == "" {
		t.Skip("UNIVERSITY_TEST_DSN is not set, integration tests are skipped")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	f := uow.NewPostgresFactory(pool)
	return f, service.NewAcademicService(f)
}

func newStudent() domain.NewStudent {
	n := time.Now().UnixNano() % 1_000_000_000_000
	return domain.NewStudent{
		RecordBookNo: fmt.Sprintf("T-%012d", n),
		LastName:     "Testenko",
		FirstName:    "Student",
		BirthDate:    time.Date(2006, 1, 2, 0, 0, 0, 0, time.UTC),
		Email:        fmt.Sprintf("t%012d@stud.univ.edu.ua", n),
		Funding:      domain.FundingContract,
	}
}

// admit admits a student and soft-deletes them after the test.
func admit(t *testing.T, svc *service.AcademicService) *service.Admission {
	t.Helper()
	ctx := context.Background()
	adm, err := svc.AdmitStudent(ctx, deanOfficeUser, testGroup, newStudent())
	if err != nil {
		t.Fatalf("AdmitStudent: %v", err)
	}
	t.Cleanup(func() { _ = svc.RemoveStudent(ctx, deanOfficeUser, adm.Student.ID) })
	return adm
}

func TestAdmitStudent_CreatesStudentAndCurriculumEnrollments(t *testing.T) {
	_, svc := setup(t)
	adm := admit(t, svc)

	if adm.Student.GroupCode != testGroup {
		t.Errorf("group = %s, expected %s", adm.Student.GroupCode, testGroup)
	}
	if len(adm.Enrollments) == 0 {
		t.Fatal("the student is not enrolled in any curriculum course")
	}
	for _, e := range adm.Enrollments {
		if e.Status != domain.EnrollmentEnrolled || e.SemesterID != adm.Semester.ID {
			t.Errorf("enrollment %d: status %s, semester %d", e.ID, e.Status, e.SemesterID)
		}
	}
	if got := deref(adm.Student.UpdatedByName); got != "Olena Koval (Dean Office)" {
		t.Errorf("updated_by_name = %q, audit fields must be filled from the UoW context", got)
	}
}

func TestUnitOfWork_RollbackDiscardsChangesOfAllRepositories(t *testing.T) {
	f, _ := setup(t)
	ctx := context.Background()

	u, err := f.Begin(ctx, deanOfficeUser)
	if err != nil {
		t.Fatal(err)
	}
	group, err := u.Groups().GetByCode(ctx, testGroup)
	if err != nil {
		t.Fatal(err)
	}
	sem, err := u.Catalog().CurrentSemester(ctx)
	if err != nil {
		t.Fatal(err)
	}
	ns := newStudent()
	ns.GroupID = group.ID
	id, err := u.Students().Create(ctx, ns)
	if err != nil {
		t.Fatal(err)
	}
	enrolled, err := u.Enrollments().EnrollByCurriculum(ctx, id, sem.ID)
	if err != nil || enrolled == 0 {
		t.Fatalf("EnrollByCurriculum = %d, %v", enrolled, err)
	}
	// the changes are visible inside the transaction
	if _, err := u.Students().GetByID(ctx, id); err != nil {
		t.Fatalf("the student is not visible in its own transaction: %v", err)
	}
	if err := u.Rollback(ctx); err != nil {
		t.Fatal(err)
	}

	err = f.Read(ctx, func(r uow.UnitOfWork) error {
		_, err := r.Students().GetByID(ctx, id)
		return err
	})
	if !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("after Rollback the student must disappear, got: %v", err)
	}
}

func TestRecordGrades_IsAllOrNothing(t *testing.T) {
	_, svc := setup(t)
	ctx := context.Background()
	adm := admit(t, svc)
	e := adm.Enrollments[0]

	_, err := svc.RecordGrades(ctx, deanOfficeUser, []domain.NewGrade{
		{EnrollmentID: e.ID, Type: domain.AssessmentModule, Title: "Module test", Score: 20, MaxScore: 20},
		{EnrollmentID: e.ID, Type: domain.AssessmentExam, Title: "Exam", Score: 40, MaxScore: 40},
		{EnrollmentID: e.ID, Type: domain.AssessmentBonus, Title: "Bonus", Score: 50, MaxScore: 50}, // 110 > 100
	})
	if !errors.Is(err, domain.ErrBusinessRule) {
		t.Fatalf("expected ErrBusinessRule, got: %v", err)
	}

	card, err := svc.GetStudentCard(ctx, adm.Student.ID)
	if err != nil {
		t.Fatal(err)
	}
	if n := len(card.Grades[e.ID]); n != 0 {
		t.Fatalf("%d grades were saved after the error, expected 0", n)
	}
}

func TestFinalizeEnrollment_ComputesGradesAndLocksEnrollment(t *testing.T) {
	_, svc := setup(t)
	ctx := context.Background()
	adm := admit(t, svc)
	e := adm.Enrollments[0]

	if _, err := svc.RecordGrades(ctx, deanOfficeUser, []domain.NewGrade{
		{EnrollmentID: e.ID, Type: domain.AssessmentModule, Title: "Module test", Score: 15, MaxScore: 20},
		{EnrollmentID: e.ID, Type: domain.AssessmentExam, Title: "Exam", Score: 30, MaxScore: 40},
		{EnrollmentID: e.ID, Type: domain.AssessmentLab, Title: "Labs", Score: 30, MaxScore: 40},
	}); err != nil {
		t.Fatal(err)
	}
	fin, err := svc.FinalizeEnrollment(ctx, deanOfficeUser, e.ID)
	if err != nil {
		t.Fatal(err)
	}
	if fin.Score != 75 || deref(fin.ECTSGrade) != "C" || fin.Status != domain.EnrollmentCompleted {
		t.Errorf("75 points: got %.0f / %s / %s", fin.Score, deref(fin.ECTSGrade), fin.Status)
	}

	_, err = svc.RecordGrades(ctx, deanOfficeUser, []domain.NewGrade{
		{EnrollmentID: e.ID, Type: domain.AssessmentBonus, Title: "Bonus", Score: 1, MaxScore: 5},
	})
	if !errors.Is(err, domain.ErrBusinessRule) {
		t.Errorf("grades of a finalized enrollment must not change, got: %v", err)
	}
}

func TestSoftDeleteAndRestore(t *testing.T) {
	f, svc := setup(t)
	ctx := context.Background()
	adm := admit(t, svc)
	id := adm.Student.ID

	if err := svc.RemoveStudent(ctx, registrarUser, id); err != nil {
		t.Fatal(err)
	}
	err := f.Read(ctx, func(u uow.UnitOfWork) error {
		if _, err := u.Students().GetByID(ctx, id); !errors.Is(err, domain.ErrNotFound) {
			return fmt.Errorf("v_students returned a deleted student: %v", err)
		}
		deleted, err := u.Students().ListDeleted(ctx)
		if err != nil {
			return err
		}
		for _, d := range deleted {
			if d.ID == id {
				if d.DeletedBy == nil || *d.DeletedBy != registrarUser {
					return fmt.Errorf("deleted_by = %v, expected %d", d.DeletedBy, registrarUser)
				}
				return nil
			}
		}
		return errors.New("the student is missing from v_students_deleted")
	})
	if err != nil {
		t.Fatal(err)
	}

	if err := svc.RemoveStudent(ctx, registrarUser, id); !errors.Is(err, domain.ErrNotFound) {
		t.Errorf("second delete: expected ErrNotFound, got %v", err)
	}
	if _, err := svc.RestoreStudent(ctx, deanOfficeUser, id); err != nil {
		t.Fatal(err)
	}

	history, err := svc.StudentHistory(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	var ops []string
	for _, h := range history {
		ops = append(ops, h.Operation)
	}
	want := []string{"INSERT", "SOFT_DELETE", "RESTORE"}
	if fmt.Sprint(ops) != fmt.Sprint(want) {
		t.Errorf("change log = %v, expected %v", ops, want)
	}
}

func TestBegin_UnknownActorIsForbidden(t *testing.T) {
	f, _ := setup(t)
	_, err := f.Begin(context.Background(), 987654321)
	if !errors.Is(err, domain.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got: %v", err)
	}
}

func TestRead_RejectsWrites(t *testing.T) {
	f, svc := setup(t)
	ctx := context.Background()
	adm := admit(t, svc)

	err := f.Read(ctx, func(u uow.UnitOfWork) error {
		return u.Students().SoftDelete(ctx, adm.Student.ID)
	})
	if err == nil {
		t.Fatal("a read-only transaction must not allow changes")
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
