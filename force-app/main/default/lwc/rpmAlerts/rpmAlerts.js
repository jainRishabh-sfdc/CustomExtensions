import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAlerts from '@salesforce/apex/RpmConsoleController.getAlerts';
import getTeam from '@salesforce/apex/RpmConsoleController.getTeam';
import checkAlert from '@salesforce/apex/RpmConsoleController.checkAlert';
import assignAlert from '@salesforce/apex/RpmConsoleController.assignAlert';
import recordCallApex from '@salesforce/apex/RpmConsoleController.recordCall';
import reviewAlert from '@salesforce/apex/RpmConsoleController.reviewAlert';
import closeAlertApex from '@salesforce/apex/RpmConsoleController.closeAlert';
import closeDeviceAlert from '@salesforce/apex/RpmConsoleController.closeDeviceAlert';
import RpmCallModal from 'c/rpmCallModal';
import { reduceError, formatDateTime, severityClass, severityLabel, navigate, DISPOSITIONS, STEPS } from 'c/rpmUtils';

const FILTERS = [
    { value: 'open', label: 'All open' },
    { value: 'critical', label: 'Critical' },
    { value: 'health', label: 'Health' },
    { value: 'device', label: 'Device' },
    { value: 'closed', label: 'Closed' }
];

export default class RpmAlerts extends LightningElement {
    @api filter;

    current = 'open';
    alerts = [];
    team = [];
    owners = {};
    dispositions = {};
    loading = false;
    error;
    dispositionOptions = DISPOSITIONS;

    connectedCallback() {
        this.current = this.filter || 'open';
        this.load();
        this.loadTeam();
    }

    async load() {
        this.loading = true;
        try {
            this.alerts = await getAlerts({ filter: this.current });
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    async loadTeam() {
        try {
            this.team = await getTeam();
        } catch (e) {
            this.team = [];
        }
    }

    get filterButtons() {
        return FILTERS.map((f) => ({ ...f, variant: f.value === this.current ? 'brand' : 'neutral' }));
    }

    changeFilter(event) {
        this.current = event.currentTarget.dataset.value;
        this.load();
    }

    get cards() {
        return this.alerts.map((a) => {
            const idx = a.stepIndex < 0 ? 0 : a.stepIndex;
            const critical = a.severity === 'Critical' && a.category === 'Health';
            const closed = a.step === 'Closed';
            return {
                ...a,
                cardClass: critical && !closed ? 'rpm-card rpm-card_crit' : 'rpm-card',
                chipClass: severityClass(a.severity),
                chipLabel: severityLabel(a.severity),
                raisedText: formatDateTime(a.raisedAt),
                dueText: a.dueAt ? 'respond by ' + formatDateTime(a.dueAt) : 'no response time',
                stepNumber: idx + 1,
                stepAria: `Progress: step ${idx + 1} of 6`,
                dots: STEPS.map((s, i) => ({
                    key: s,
                    text: i < idx || closed ? '✓' : String(i + 1),
                    cls: i < idx || closed ? 'rpm-dot rpm-dot_done' : i === idx ? 'rpm-dot rpm-dot_cur' : 'rpm-dot',
                    line: i < STEPS.length - 1,
                    lineCls: i < idx ? 'rpm-line rpm-line_done' : 'rpm-line'
                })),
                isClosed: closed,
                isDevice: !closed && a.category === 'Device',
                atNew: a.step === 'New',
                atChecked: a.step === 'Checked',
                atAssigned: a.step === 'Assigned',
                atCalled: a.step === 'Patient Called',
                atReviewed: a.step === 'Provider Reviewed',
                callLabel: critical ? 'Record patient call (required)' : 'Record patient call',
                callVariant: critical ? 'destructive' : 'brand',
                historyRows: (a.history || []).map((h) => ({
                    id: h.id,
                    when: formatDateTime(h.at),
                    by: h.by,
                    text: (h.from ? `${h.from} → ${h.to}` : h.to) + (h.detail ? ` — ${h.detail}` : '')
                }))
            };
        });
    }

    get noCards() {
        return !this.loading && this.alerts.length === 0;
    }

    find(id) {
        return this.alerts.find((a) => a.id === id);
    }

    async run(action, successMessage) {
        try {
            await action();
            this.toast(successMessage, 'success');
            await this.load();
        } catch (e) {
            this.toast(reduceError(e), 'error');
        }
    }

    markChecked(event) {
        const id = event.currentTarget.dataset.id;
        this.run(() => checkAlert({ alertId: id, note: null }), 'Checked — next: assign an owner');
    }

    chooseOwner(event) {
        this.owners = { ...this.owners, [event.target.dataset.id]: event.detail.value };
    }

    assign(event) {
        const id = event.currentTarget.dataset.id;
        const userId = this.owners[id];
        if (!userId) {
            this.toast('Choose an owner first', 'warning');
            return;
        }
        this.run(() => assignAlert({ alertId: id, userId }), 'Assigned — next: call the patient');
    }

    async recordCall(event) {
        const id = event.currentTarget.dataset.id;
        const a = this.find(id);
        const result = await RpmCallModal.open({
            size: 'small',
            label: 'Record patient call',
            patientName: a.patientName,
            summary: a.summary,
            severity: a.severity
        });
        if (!result) {
            return;
        }
        this.run(
            () =>
                recordCallApex({
                    alertId: id,
                    outcome: result.outcome,
                    symptoms: result.symptoms || null,
                    providerNotified: result.provider || null,
                    note: result.note || null
                }),
            'Call recorded — next: provider review'
        );
    }

    reviewed(event) {
        const id = event.currentTarget.dataset.id;
        this.run(() => reviewAlert({ alertId: id, note: null }), 'Provider review recorded — choose what was done, then close');
    }

    chooseDisposition(event) {
        this.dispositions = { ...this.dispositions, [event.target.dataset.id]: event.detail.value };
    }

    closeAlert(event) {
        const id = event.currentTarget.dataset.id;
        const disposition = this.dispositions[id];
        if (!disposition) {
            this.toast('Choose what was done first', 'warning');
            return;
        }
        this.run(() => closeAlertApex({ alertId: id, disposition }), 'Alert closed: ' + disposition);
    }

    fixDevice(event) {
        const id = event.currentTarget.dataset.id;
        this.run(() => closeDeviceAlert({ alertId: id, note: null }), 'Device issue closed');
    }

    openPatient(event) {
        navigate(this, 'patients', { patientId: event.currentTarget.dataset.id });
    }

    goDevices() {
        navigate(this, 'devices', {});
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
