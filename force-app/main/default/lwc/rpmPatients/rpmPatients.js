import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPatients from '@salesforce/apex/RpmConsoleController.getPatients';
import getPatientDetail from '@salesforce/apex/RpmConsoleController.getPatientDetail';
import logTimeApex from '@salesforce/apex/RpmConsoleController.logTime';
import {
    reduceError,
    formatDateTime,
    formatDate,
    riskClass,
    riskLabel,
    severityClass,
    severityLabel,
    daysAgo,
    navigate,
    parseCodes,
    meter,
    ACTIVITIES
} from 'c/rpmUtils';

export default class RpmPatients extends LightningElement {
    @api patientId;
    @api risk;
    @api presetMinutes;

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

    connectedCallback() {
        if (this.presetMinutes) {
            this.minutes = this.presetMinutes;
        }
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
            this.dispatchEvent(
                new CustomEvent('rpmpatientselect', { detail: { id: this.detail.id, name: this.detail.name }, bubbles: true, composed: true })
            );
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loadingDetail = false;
        }
    }

    // ---------- roster

    get riskText() {
        return riskLabel(this.risk).toLowerCase();
    }

    get rosterRows() {
        const q = this.search.toLowerCase();
        return this.patients
            .filter((p) => !q || (p.name || '').toLowerCase().includes(q))
            .map((p) => {
                const ago = daysAgo(p.lastReading);
                return {
                    ...p,
                    rowClass: p.id === this.selectedId ? 'rpm-rrow rpm-rrow_on' : 'rpm-rrow',
                    riskClass: riskClass(p.risk),
                    riskText: riskLabel(p.risk),
                    subtitle: [p.payer, ago === null ? 'no readings yet' : ago === 0 ? 'read today' : `last read ${ago}d ago`].filter((x) => x).join(', ')
                };
            });
    }

    get rosterCount() {
        return this.rosterRows.length;
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

    get detailRiskText() {
        return riskLabel(this.detail.risk);
    }

    get noConsent() {
        return !this.detail.consentDate;
    }

    get detailFacts() {
        const d = this.detail;
        return [d.sex, d.diagnoses, d.payer, d.payerType].filter((x) => x).join(', ');
    }

    get recordUrl() {
        return '/' + this.detail.id;
    }

    get rangeButtons() {
        return [7, 30, 90].map((d) => ({ days: d, label: `${d} days`, cls: d === this.days ? 'rpm-seg__on' : '' }));
    }

    get deviceTags() {
        return (this.detail.devices || []).map((d) => ({
            id: d.id,
            text: `Cuff ${d.serial || d.name}, ${d.battery ?? '?'}% battery${d.silent ? ', silent' : ''}`,
            cls: d.silent || d.lowBattery ? 'rpm-tag rpm-tag_amber' : 'rpm-tag rpm-tag_slate'
        }));
    }

    changeRange(event) {
        this.days = Number(event.currentTarget.dataset.days);
        this.loadDetail(this.selectedId);
    }

    // ---------- readout strip under the chart

    get readout() {
        const rs = this.detail.readings || [];
        const avg = (k) => {
            const vals = rs.map((r) => Number(r[k])).filter((v) => !isNaN(v));
            return vals.length ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length) : '—';
        };
        const last = rs.length ? rs[rs.length - 1] : null;
        return [
            { k: 'Latest', v: last ? `${last.sys}/${last.dia ?? '?'}` : '—' },
            { k: 'Average systolic', v: avg('sys') },
            { k: 'Average diastolic', v: avg('dia') },
            { k: 'Readings in range', v: rs.length }
        ];
    }

    // ---------- care time

    get activityOptions() {
        return ACTIVITIES.map((a) => ({ ...a, selected: a.value === this.activity }));
    }

    get timeRows() {
        return (this.detail.time || []).map((t) => ({ ...t, when: formatDate(t.date) }));
    }

    get totalMinutes() {
        return (this.detail.time || []).reduce((sum, t) => sum + Number(t.minutes || 0), 0);
    }

    handleActivity(event) {
        this.activity = event.target.value;
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
            this.toast('Enter between 1 and 240 minutes', 'warning');
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
            this.minutes = 5;
            this.toast(`Logged ${mins} min for ${this.detail.name}`, 'success');
            await this.loadDetail(this.detail.id);
        } catch (e) {
            this.toast(reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    // ---------- billing

    get billing() {
        return this.detail.billing || { readingDays: 0, minutes: 0, status: 'Accruing', rulesVersion: '' };
    }

    get daysMeter() {
        return meter(this.billing.readingDays, 16);
    }

    get minutesMeter() {
        return meter(this.billing.minutes, 20);
    }

    get codePills() {
        return parseCodes(this.billing.codes);
    }

    get hasCodes() {
        return this.codePills.length > 0;
    }

    get billingStatusClass() {
        const s = this.billing.status;
        return s === 'Ready to Bill' || s === 'Billed' ? 'rpm-tag rpm-tag_emerald' : s === 'Blocked' ? 'rpm-tag rpm-tag_rose' : 'rpm-tag rpm-tag_amber';
    }

    // ---------- alerts

    get alertRows() {
        return (this.detail.alerts || []).map((a) => ({ ...a, chipClass: severityClass(a.severity), severityText: severityLabel(a.severity), dueText: formatDateTime(a.dueAt) }));
    }

    get alertCount() {
        return this.alertRows.length;
    }

    get noAlerts() {
        return this.alertRows.length === 0;
    }

    goAlerts() {
        navigate(this, 'alerts', { filter: 'open' });
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
