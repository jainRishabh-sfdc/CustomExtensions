import { LightningElement } from 'lwc';
import getToday from '@salesforce/apex/RpmConsoleController.getToday';
import { reduceError, formatDateTime, navigate } from 'c/rpmUtils';

export default class RpmToday extends LightningElement {
    data;
    error;
    loading = true;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getToday();
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    get stats() {
        const d = this.data || {};
        return [
            { key: 'crit', value: d.critical, label: 'Critical readings waiting for a call', tone: 'rose', tab: 'alerts', filter: 'critical' },
            { key: 'red', value: d.redPatients, label: 'Patients flagged red', tone: 'rose', tab: 'patients', risk: 'RED' },
            { key: 'over', value: d.overdue, label: 'Alerts past their response time', tone: 'amber', tab: 'alerts', filter: 'open' },
            { key: 'dev', value: d.deviceOpen, label: 'Cuffs that need attention', tone: 'amber', tab: 'devices' },
            { key: 'bill', value: d.readyToBill, label: 'Billing periods ready to bill', tone: 'emerald', tab: 'billing' },
            { key: 'pts', value: d.patients, label: 'Patients on the program', tone: 'indigo', tab: 'patients' }
        ].map((s) => ({ ...s, cls: `rpm-stat rpm-stat_${s.tone}` }));
    }

    get queue() {
        return ((this.data && this.data.todo) || []).map((t) => {
            const urgentTone = t.overdue || t.severity === 'Critical' ? 'rose' : t.severity === 'Urgent' ? 'amber' : 'indigo';
            return {
                ...t,
                whenClass: `rpm-tag rpm-tag_${urgentTone} rpm-when`,
                whenLabel: t.overdue ? 'Overdue' : t.severity === 'Critical' ? 'Now' : t.severity === 'Urgent' ? 'Today' : 'This week',
                metaText: `${t.step}, ${t.owner ? t.owner : 'no owner yet'}${t.dueAt ? ', respond by ' + formatDateTime(t.dueAt) : ''}`,
                buttonClass: t.severity === 'Critical' ? 'rpm-btn rpm-btn_danger' : 'rpm-btn',
                filter: t.category === 'Device' ? 'device' : t.severity === 'Critical' ? 'critical' : 'health'
            };
        });
    }

    get openCount() {
        return this.data ? this.data.healthOpen + this.data.deviceOpen : 0;
    }

    get queueEmpty() {
        return this.queue.length === 0;
    }

    handleStat(event) {
        const { tab, filter, risk } = event.currentTarget.dataset;
        navigate(this, tab, { filter: filter || undefined, risk: risk || undefined });
    }

    openPatient(event) {
        navigate(this, 'patients', { patientId: event.currentTarget.dataset.id });
    }

    openAlert(event) {
        navigate(this, 'alerts', { filter: event.currentTarget.dataset.filter });
    }
}
