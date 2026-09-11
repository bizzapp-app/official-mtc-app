# MercyLife Training College ERP

Production-oriented school management application for MercyLife Training College.

## Lifecycle
**Admissions → Student Registration → Enrollment → Finance → Attendance → Assignments → Clinical → Exams → Results → Certificates → Graduation → Alumni**

## Main modules
- Admissions & applicant conversion
- Student records
- Courses & units
- Academic years / intakes
- Attendance
- Examinations & results
- Finance, invoices, payments and receipts
- Clinical rotations
- Assignments & submissions
- Library
- Messaging / announcements
- Documents & certificates
- Graduation & alumni
- Reports & analytics
- User accounts & role-based access
- Audit logging
- Persistent light/dark themes
- Direct College Website navigation

## Security model
Supabase Auth is authoritative. Only the bootstrap administrator is created directly in Supabase. Subsequent staff/student accounts are created by authorized administrators through the admin panel.

Never commit `.env` files or Supabase service-role secrets.
