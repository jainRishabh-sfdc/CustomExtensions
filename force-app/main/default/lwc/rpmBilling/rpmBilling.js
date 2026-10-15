import { LightningElement } from 'lwc';
import getBilling from '@salesforce/apex/RpmConsoleController.getBilling';
import { reduceError, formatDate, navigate, parseCodes, meter, billingAudit } from 'c/rpmUtils';

export default class RpmBilling extends LightningElement {
    data = [];
    openAudit = {};
    loading = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getBilling();
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        return [...this.data]
            .sort((a, b) => (a.patientName || '').localeCompare(b.patientName || ''))
            .map((r) => {
                const pills = parseCodes(r.codes);
                const open = !!this.openAudit[r.patientId];
                return {
                    ...r,
                    pills,
                    hasCodes: pills.length > 0,
                    daysMeter: meter(r.readingDays, 16),
                    minutesMeter: meter(r.minutes, 20),
                    interactiveText: r.interactive ? 'Interactive' : 'Not interactive',
                    open,
                    expanded: open ? 'true' : 'false',
                    auditLabel: open ? 'Hide audit' : 'Audit',
                    auditKey: r.patientId + '-audit',
                    audit: billingAudit(r).map((text, i) => ({ key: r.patientId + '-' + i, text }))
                };
            });
    }

    toggleAudit(event) {
        const id = event.currentTarget.dataset.id;
        this.openAudit = { ...this.openAudit, [id]: !this.openAudit[id] };
    }

    get noRows() {
        return !this.loading && this.data.length === 0;
    }
    get earning() {
        return this.data.filter((r) => r.codes).length;
    }
    get codeUnits() {
        return this.data.reduce((n, r) => n + parseCodes(r.codes).reduce((m, c) => m + c.units, 0), 0);
    }
    get blocked() {
        return this.data.filter((r) => r.status === 'Blocked').length;
    }
    get notYet() {
        return this.data.filter((r) => !r.codes && r.status !== 'Blocked').length;
    }

    get periodLabel() {
        const first = this.data[0];
        if (!first) {
            return 'This month';
        }
        const d = new Date(first.periodStart + 'T12:00:00');
        return d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' }) + ` (${formatDate(first.periodStart)} – ${formatDate(first.periodEnd)})`;
    }

    get rulesVersion() {
        const first = this.data[0];
        return first && first.rulesVersion ? 'Rules ' + first.rulesVersion : 'Rules';
    }

    openPatient(event) {
        navigate(this, 'patients', { patientId: event.currentTarget.dataset.id });
    }
}
