import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPatients from '@salesforce/apex/RpmConsoleController.getPatients';
import getPatientDetail from '@salesforce/apex/RpmConsoleController.getPatientDetail';
import logTimeApex from '@salesforce/apex/RpmConsoleController.logTime';
import { reduceError, formatDateTime, formatDate, riskClass, severityClass, daysAgo, navigate, ACTIVITIES } from 'c/rpmUtils';

export default class RpmPatients extends LightningElement {
    @api patientId;
    @api risk;

    patients = [];
    selectedId;
    search = '';
    detail;
    error;
    loadingDetail = false;
    days = 30;

    activity = 'Reviewed readings';
    minutes = 5;
    interactive = false;
    note = '';
    saving = false;

    activityOptions = ACTIVITIES;

    connectedCallback() {
        this.loadPatients();
    }

    async loadPatients() {
        try {
            this.patients = await getPatients({ risk: this.risk || null });
            this.error = undefined;
            const target = this.patientId || (this.patients.length ? this.patients[0].id : null);
            if (target) {
                this.loadDetail(target);
            }
        } catch (e) {
            this.error = reduceError(e);
        }
    }

    async loadDetail(id) {
        this.selectedId = id;
        this.loadingDetail = true;
        try {
            this.detail = await getPatientDetail({ patientId: id, days: this.days });
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loadingDetail = false;
        }
    }

    // ---------- roster

    get rosterRows() {
        const q = this.search.toLowerCase();
        return this.patients
            .filter((p) => !q || (p.name || '').toLowerCase().includes(q))
            .map((p) => {
                const ago = daysAgo(p.lastReading);
                return {
                    ...p,
                    rowClass: p.id === this.selectedId ? 'rpm-roster__row rpm-roster__row_on' : 'rpm-roster__row',
                    riskClass: riskClass(p.risk),
                    subtitle: [p.payer, ago === null ? 'no readings yet' : ago === 0 ? 'read today' : `last read ${ago}d ago`]
                        .filter((x) => x)
                        .join(' · ')
                };
            });
    }

    get noPatients() {
        return this.rosterRows.length === 0;
    }

    get noSelection() {
        return !this.loadingDetail && !this.detail;
    }

    handleSearch(event) {
        this.search = event.target.value || '';
    }

    selectPatient(event) {
        this.loadDetail(event.currentTarget.dataset.id);
    }

    clearRisk() {
        navigate(this, 'patients', {});
    }

    // ---------- header

    get detailRiskClass() {
        return riskClass(this.detail.risk);
    }

    get noConsent() {
        return !this.detail.consentDate;
    }

    get detailSubtitle() {
        const d = this.detail;
        return [d.sex, d.diagnoses, d.payer, d.payerType].filter((x) => x).join(' · ');
    }

    get recordUrl() {
        return '/' + this.detail.id;
    }

    get rangeButtons() {
        return [7, 30, 90].map((d) => ({ days: d, label: `${d} days`, variant: d === this.days ? 'brand' : 'neutral' }));
    }

    get deviceChips() {
        return (this.detail.devices || []).map((d) => ({
            id: d.id,
            text: `${d.serial || d.name} · battery ${d.battery ?? '?'}%${d.silent ? ' · silent' : ''}`,
            cls: d.silent || d.lowBattery ? 'rpm-chip rpm-chip_crit' : 'rpm-chip rpm-chip_ok'
        }));
    }

    changeRange(event) {
        this.days = Number(event.currentTarget.dataset.days);
        this.loadDetail(this.selectedId);
    }

    // ---------- readings & stats

    get readingRows() {
        return [...(this.detail.readings || [])].reverse().map((r) => ({
            ...r,
            when: formatDateTime(r.at),
            flagLabel: r.flag === 'critical' ? 'CRITICAL' : r.flag === 'high' ? 'above call line' : r.flag === 'low' ? 'below low line' : null,
            flagClass: r.flag === 'critical' ? 'rpm-chip rpm-chip_crit' : 'rpm-chip rpm-chip_hot'
        }));
    }

    get noReadings() {
        return !this.detail.readings || this.detail.readings.length === 0;
    }

    get stats() {
        const rs = this.detail.readings || [];
        const sys = rs.map((r) => Number(r.sys)).filter((v) => !isNaN(v));
        const dia = rs.map((r) => Number(r.dia)).filter((v) => !isNaN(v));
        const calc = (vals) => {
            if (!vals.length) {
                return { avg: '—', max: '—', med: '—', min: '—' };
            }
            const s = [...vals].sort((a, b) => a - b);
            const mid = Math.floor(s.length / 2);
            const med = s.length % 2 ? s[mid] : Math.round((s[mid - 1] + s[mid]) / 2);
            return { avg: (vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1), max: s[s.length - 1], med, min: s[0] };
        };
        const a = calc(sys);
        const b = calc(dia);
        return [
            { label: 'Average', sys: a.avg, dia: b.avg },
            { label: 'Highest', sys: a.max, dia: b.max },
            { label: 'Typical (median)', sys: a.med, dia: b.med },
            { label: 'Lowest', sys: a.min, dia: b.min },
            { label: 'Readings', sys: sys.length, dia: dia.length }
        ];
    }

    // ---------- care time

    get timeRows() {
        return (this.detail.time || []).map((t) => ({ ...t, when: formatDate(t.date) }));
    }

    get totalMinutes() {
        return (this.detail.time || []).reduce((sum, t) => sum + Number(t.minutes || 0), 0);
    }

    handleActivity(event) {
        this.activity = event.detail.value;
        if (this.activity === 'Phone call with patient' || this.activity === 'Call with caregiver') {
            this.interactive = true;
        }
    }
    handleMinutes(event) {
        this.minutes = event.target.value;
    }
    handleInteractive(event) {
        this.interactive = event.target.checked;
    }
    handleNote(event) {
        this.note = event.target.value;
    }

    async logTime() {
        const mins = parseInt(this.minutes, 10);
        if (!mins || mins < 1 || mins > 240) {
            this.toast('Check minutes', 'Enter between 1 and 240 minutes.', 'warning');
            return;
        }
        this.saving = true;
        try {
            await logTimeApex({
                patientId: this.detail.id,
                minutes: mins,
                activity: this.activity,
                interactive: this.interactive,
                note: this.note
            });
            this.note = '';
            this.toast('Time logged', `${mins} min logged for ${this.detail.name}`, 'success');
            await this.loadDetail(this.detail.id);
        } catch (e) {
            this.toast('Could not log time', reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    // ---------- billing

    get billing() {
        return this.detail.billing || { readingDays: 0, minutes: 0, status: 'Accruing', rulesVersion: '' };
    }

    get daysBarStyle() {
        const pct = Math.min(100, (Number(this.billing.readingDays || 0) / 16) * 100);
        return `width:${pct}%;background:${pct >= 100 ? '#177245' : '#9a6b10'}`;
    }

    get minutesBarStyle() {
        const pct = Math.min(100, (Number(this.billing.minutes || 0) / 20) * 100);
        return `width:${pct}%;background:${pct >= 100 ? '#177245' : '#9a6b10'}`;
    }

    get billingStatusClass() {
        const s = this.billing.status;
        return s === 'Ready to Bill' || s === 'Billed' ? 'rpm-chip rpm-chip_ok' : s === 'Blocked' ? 'rpm-chip rpm-chip_crit' : 'rpm-chip rpm-chip_warn';
    }

    // ---------- alerts

    get alertRows() {
        return (this.detail.alerts || []).map((a) => ({ ...a, chipClass: severityClass(a.severity) }));
    }

    get noAlerts() {
        return this.alertRows.length === 0;
    }

    goAlerts() {
        navigate(this, 'alerts', {});
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
