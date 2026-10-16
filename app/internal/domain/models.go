// Package domain contains the domain models of the university management system.
// The models do not depend on storage: repositories fill them from
// PostgreSQL views and stored procedure results.
package domain

import (
	"encoding/json"
	"time"
)

type StudentStatus string

const (
	StudentActive        StudentStatus = "active"
	StudentAcademicLeave StudentStatus = "academic_leave"
	StudentExpelled      StudentStatus = "expelled"
	StudentGraduated     StudentStatus = "graduated"
)

type FundingType string

const (
	FundingBudget   FundingType = "budget"
	FundingContract FundingType = "contract"
)

type EnrollmentStatus string

const (
	EnrollmentEnrolled  EnrollmentStatus = "enrolled"
	EnrollmentCompleted EnrollmentStatus = "completed"
	EnrollmentFailed    EnrollmentStatus = "failed"
	EnrollmentDropped   EnrollmentStatus = "dropped"
)

type AssessmentType string

const (
	AssessmentLab        AssessmentType = "lab"
	AssessmentPractice   AssessmentType = "practice"
	AssessmentTest       AssessmentType = "test"
	AssessmentModule     AssessmentType = "module"
	AssessmentCoursework AssessmentType = "coursework"
	AssessmentExam       AssessmentType = "exam"
	AssessmentBonus      AssessmentType = "bonus"
)

// Student is an active student (a row of v_students).
type Student struct {
	ID             int64
	RecordBookNo   string
	LastName       string
	FirstName      string
	MiddleName     *string
	FullName       string
	BirthDate      time.Time
	Email          *string
	Phone          *string
	EnrollmentDate time.Time
	Status         StudentStatus
	Funding        FundingType
	GroupID        int64
	GroupCode      string
	StudyYear      int
	SpecialtyID    int64
	Specialty      string
	FacultyID      int64
	Faculty        string
	Curator        *string
	CreatedAt      time.Time
	UpdatedAt      time.Time
	UpdatedByName  *string
}

// NewStudent holds the data for admitting a student (sp_student_create).
type NewStudent struct {
	GroupID      int64
	RecordBookNo string
	LastName     string
	FirstName    string
	MiddleName   string
	BirthDate    time.Time
	Email        string
	Phone        string
	Funding      FundingType
}

// StudentUpdate holds the editable personal data of a student (sp_student_update).
type StudentUpdate struct {
	LastName   string
	FirstName  string
	MiddleName string
	BirthDate  time.Time
	Email      string
	Phone      string
	Funding    FundingType
}

// StudentFilter holds the parameters for listing students.
type StudentFilter struct {
	GroupID *int64
	Status  *StudentStatus
	Limit   int
	Offset  int
}

// StudentSearchResult is a fuzzy search result (fn_search_students).
type StudentSearchResult struct {
	StudentID    int64
	FullName     string
	GroupCode    string
	RecordBookNo string
	Similarity   float32
}

// DeletedStudent is a soft-deleted student (v_students_deleted).
type DeletedStudent struct {
	ID            int64
	RecordBookNo  string
	FullName      string
	GroupCode     string
	Status        StudentStatus
	DeletedAt     time.Time
	DeletedBy     *int64
	DeletedByName *string
}

// Group is a student group (v_groups).
type Group struct {
	ID             int64
	Code           string
	AdmissionYear  int
	StudyYear      int
	MaxSize        int
	SpecialtyID    int64
	Specialty      string
	DegreeLevel    string
	Faculty        string
	Curator        *string
	ActiveStudents int64
	BudgetStudents int64
	OnLeave        int64
}

// RatingEntry is a row of a group ranking (fn_group_rating).
type RatingEntry struct {
	Place     int64
	StudentID int64
	FullName  string
	Funding   FundingType
	Rating    *float64
	Credits   float64
	Debts     int64
}

// Semester is an academic semester (v_semesters).
type Semester struct {
	ID           int64
	AcademicYear string
	Term         int
	Name         string
	StartDate    time.Time
	EndDate      time.Time
	IsCurrent    bool
	IsClosed     bool
}

// Course is a course (v_courses).
type Course struct {
	ID            int64
	Code          string
	Name          string
	Credits       float64
	LectureHours  int
	PracticeHours int
	LabHours      int
	Control       string
	DepartmentID  int64
	Department    string
}

// Enrollment is a student enrollment in a course (v_enrollments).
type Enrollment struct {
	ID            int64
	StudentID     int64
	StudentName   string
	GroupCode     string
	CourseID      int64
	CourseCode    string
	CourseName    string
	Credits       float64
	Control       string
	SemesterID    int64
	Semester      string
	Status        EnrollmentStatus
	Score         float64
	ECTSGrade     *string
	NationalGrade *string
	EnrolledAt    time.Time
	FinalizedAt   *time.Time
	UpdatedAt     time.Time
}

// SemesterResult holds the semester results of a student (v_student_semester_results).
type SemesterResult struct {
	StudentID     int64
	FullName      string
	GroupCode     string
	SemesterID    int64
	Semester      string
	CoursesTotal  int64
	CoursesPassed int64
	Debts         int64
	CreditsTotal  float64
	CreditsEarned float64
	Rating        *float64
}

// Grade is an assessment grade (v_grades).
type Grade struct {
	ID            int64
	EnrollmentID  int64
	StudentID     int64
	StudentName   string
	CourseName    string
	SemesterID    int64
	Type          AssessmentType
	Title         string
	Score         float64
	MaxScore      float64
	GradedOn      time.Time
	TeacherID     *int64
	TeacherName   *string
	Comment       *string
	UpdatedAt     time.Time
	UpdatedByName *string
}

// NewGrade holds the data for adding a grade (sp_grade_add).
type NewGrade struct {
	EnrollmentID int64
	Type         AssessmentType
	Title        string
	Score        float64
	MaxScore     float64
	TeacherID    *int64
	Comment      string
}

// ChangeRecord is a change log entry (v_change_history).
type ChangeRecord struct {
	ID            int64
	ChangedAt     time.Time
	TableName     string
	RecordID      int64
	Operation     string
	ChangedFields []string
	ChangedBy     *int64
	ChangedByName string
	OldData       json.RawMessage
	NewData       json.RawMessage
}
