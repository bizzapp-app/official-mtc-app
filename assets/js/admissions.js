import { renderNavbar } from './components/navbar.js';
import { renderSidebar } from './components/sidebar.js';
import { dbService } from './supabase.js';
import { enforcePageAccess, getCurrentUser } from './auth.js';
import { createModal } from './components/modal.js';
import { showToast } from './components/toast.js';

let admissions = [];
let courses = [];
let intakes = [];

document.addEventListener('DOMContentLoaded', async () => {
  const allowed = await enforcePageAccess(['administrator','principal','registrar','reception']);
  if (!allowed) return;
  await renderSidebar('admissions');
  await renderNavbar('Admissions & Applicant Management');
  await load();
  document.getElementById('new-admission-btn')?.addEventListener('click', () => openAdmissionModal());
  document.getElementById('refresh-admissions')?.addEventListener('click', load);
  document.getElementById('admission-search')?.addEventListener('input', render);
  document.getElementById('admission-status')?.addEventListener('change', render);
});

async function load() {
  try {
    [admissions, courses, intakes] = await Promise.all([dbService.getAdmissions(), dbService.getCourses(), dbService.getIntakes()]);
    render();
  } catch (e) { showToast(e.message || 'Could not load admissions.', 'error'); }
}

function render() {
  const q = (document.getElementById('admission-search')?.value || '').toLowerCase();
  const status = document.getElementById('admission-status')?.value || '';
  const rows = admissions.filter(a => (!status || a.status === status) && (!q || `${a.full_name} ${a.application_no} ${a.email}`.toLowerCase().includes(q)));
  const tbody = document.getElementById('admissions-tbody');
  if (!tbody) return;
  tbody.innerHTML = rows.length ? rows.map(a => `
    <tr><td><strong>${esc(a.application_no)}</strong></td><td>${esc(a.full_name)}<div style="font-size:.75rem;color:var(--text-muted)">${esc(a.email)}</div></td><td>${esc(a.course_name || 'Not assigned')}</td><td>${esc(a.intake_name || 'Not assigned')}</td><td>${esc(a.application_date || '')}</td><td><span class="badge-pill badge-${a.status === 'converted' ? 'success' : a.status === 'rejected' ? 'danger' : 'primary'}">${esc(a.status)}</span></td><td><div style="display:flex;gap:.35rem;flex-wrap:wrap">${a.status !== 'converted' ? `<button class="btn btn-sm btn-outline review-btn" data-id="${a.id}">Review</button>` : ''}${['submitted','under_review','accepted'].includes(a.status) ? `<button class="btn btn-sm btn-primary convert-btn" data-id="${a.id}">Admit Student</button>` : ''}</div></td></tr>
  `).join('') : '<tr><td colspan="7" style="text-align:center;padding:2rem">No applications found.</td></tr>';
  tbody.querySelectorAll('.review-btn').forEach(b => b.onclick = () => openAdmissionModal(admissions.find(a => a.id === b.dataset.id)));
  tbody.querySelectorAll('.convert-btn').forEach(b => b.onclick = () => convert(b.dataset.id));
}

function openAdmissionModal(existing=null) {
  const isEdit = !!existing;
  createModal({
    title: isEdit ? `Review ${existing.application_no}` : 'New Admission Application',
    bodyHTML: `<form id="admission-form"><div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem">
      <div class="form-group"><label class="form-label">Full Name *</label><input class="form-control" id="a-name" required value="${esc(existing?.full_name||'')}"></div>
      <div class="form-group"><label class="form-label">Gender *</label><select class="form-control" id="a-gender"><option ${existing?.gender==='Female'?'selected':''}>Female</option><option ${existing?.gender==='Male'?'selected':''}>Male</option><option ${existing?.gender==='Other'?'selected':''}>Other</option></select></div>
      <div class="form-group"><label class="form-label">Date of Birth</label><input type="date" class="form-control" id="a-dob" value="${esc(existing?.dob||'')}"></div>
      <div class="form-group"><label class="form-label">National ID</label><input class="form-control" id="a-id" value="${esc(existing?.national_id||'')}"></div>
      <div class="form-group"><label class="form-label">Phone *</label><input class="form-control" id="a-phone" required value="${esc(existing?.phone||'')}"></div>
      <div class="form-group"><label class="form-label">Email *</label><input type="email" class="form-control" id="a-email" required value="${esc(existing?.email||'')}"></div>
      <div class="form-group"><label class="form-label">Course *</label><select class="form-control" id="a-course" required><option value="">Select course</option>${courses.map(c=>`<option value="${c.id}" ${existing?.course_id===c.id?'selected':''}>${esc(c.code)} - ${esc(c.name)}</option>`).join('')}</select></div>
      <div class="form-group"><label class="form-label">Intake</label><select class="form-control" id="a-intake"><option value="">Select intake</option>${intakes.map(i=>`<option value="${i.id}" ${existing?.intake_id===i.id?'selected':''}>${esc(i.name)}</option>`).join('')}</select></div>
      <div class="form-group"><label class="form-label">KCSE Grade</label><input class="form-control" id="a-kcse" value="${esc(existing?.kcse_grade||'')}"></div>
      <div class="form-group"><label class="form-label">County</label><input class="form-control" id="a-county" value="${esc(existing?.county||'')}"></div>
      <div class="form-group"><label class="form-label">Guardian Name</label><input class="form-control" id="a-guardian" value="${esc(existing?.guardian_name||'')}"></div>
      <div class="form-group"><label class="form-label">Guardian Phone</label><input class="form-control" id="a-gphone" value="${esc(existing?.guardian_phone||'')}"></div>
    </div><div class="form-group"><label class="form-label">Address</label><input class="form-control" id="a-address" value="${esc(existing?.address||'')}"></div><div class="form-group"><label class="form-label">Status</label><select class="form-control" id="a-status"><option value="submitted">submitted</option><option value="under_review">under_review</option><option value="accepted">accepted</option><option value="rejected">rejected</option><option value="converted">converted</option></select></div><div class="form-group"><label class="form-label">Notes</label><textarea class="form-control" id="a-notes" rows="3">${esc(existing?.notes||'')}</textarea></div></form>`,
    footerHTML:`<button class="btn btn-secondary" id="cancel-a">Cancel</button><button class="btn btn-primary" id="save-a">${isEdit?'Save Review':'Create Application'}</button>`,
    onOpen:(close)=>{
      if(existing) document.getElementById('a-status').value=existing.status;
      document.getElementById('cancel-a').onclick=close;
      document.getElementById('save-a').onclick=async()=>{
        const payload={full_name:v('a-name'),gender:v('a-gender'),dob:v('a-dob')||null,national_id:v('a-id')||null,phone:v('a-phone'),email:v('a-email'),course_id:v('a-course'),intake_id:v('a-intake')||null,kcse_grade:v('a-kcse')||null,county:v('a-county')||null,guardian_name:v('a-guardian')||null,guardian_phone:v('a-gphone')||null,address:v('a-address')||null,status:v('a-status'),notes:v('a-notes')||null};
        try { if(isEdit) await dbService.updateAdmission(existing.id,payload); else await dbService.addAdmission(payload); showToast('Admission record saved.'); close(); await load(); } catch(e){showToast(e.message||'Could not save admission.','error');}
      };
    }
  });
}

async function convert(id){
  const a=admissions.find(x=>x.id===id); if(!a) return;
  if(a.status==='submitted') { try { await dbService.updateAdmission(id,{status:'accepted'}); } catch(e){ showToast(e.message,'error'); return; } }
  if(!confirm(`Convert ${a.full_name} into an official student and generate an admission number?`)) return;
  try { const result=await dbService.convertAdmissionToStudent(id); showToast(`Student admitted: ${result.admission_no}`); await load(); } catch(e){showToast(e.message||'Admission conversion failed.','error');}
}
function v(id){return document.getElementById(id)?.value?.trim()||''}
function esc(x){return String(x??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
