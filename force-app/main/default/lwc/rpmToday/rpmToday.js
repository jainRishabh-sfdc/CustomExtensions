import { LightningElement } from 'lwc';
import getToday from '@salesforce/apex/RpmConsoleController.getToday';
import { reduceError, formatDateTime, severityClass, navigate } from 'c/rpmUtils';

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

    get kpis() {
        const d = this.data || {};
        return [
            { key: 'crit', value: d.critical, label: 'Critical alerts — act now', cls: 'rpm-kpi rpm-kpi_crit', tab: 'alerts', filter: 'critical' },
            { key: 'red', value: d.redPatients, label: 'Patients at RED risk', cls: 'rpm-kpi rpm-kpi_crit', tab: 'patients', risk: 'RED' },
            { key: 'overdue', value: d.overdue, label: 'Alerts past their response time', cls: 'rpm-kpi rpm-kpi_hot', tab: 'alerts' },
            { key: 'health', value: d.healthOpen, label: 'Health alerts open', cls: 'rpm-kpi rpm-kpi_hot', tab: 'alerts', filter: 'health' },
            { key: 'device', value: d.deviceOpen, label: 'Device issues open', cls: 'rpm-kpi rpm-kpi_warn', tab: 'devices' },
            { key: 'bill', value: d.readyToBill, label: 'Billing periods ready to bill', cls: 'rpm-kpi rpm-kpi_ok', tab: 'billing' },
            { key: 'pts', value: d.patients, label: 'Patients on the program', cls: 'rpm-kpi rpm-kpi_ok', tab: 'patients' }
        ];
    }

    get todo() {
        return ((this.data && this.data.todo) || []).map((t) => ({
            ...t,
            chipClass: severityClass(t.severity) + ' rpm-todo__chip',
            chipLabel: t.overdue ? 'OVERDUE' : t.severity === 'Critical' ? 'NOW' : t.severity === 'Urgent' ? 'TODAY' : 'THIS WEEK',
            ownerText: t.owner ? 'owner ' + t.owner : 'unassigned',
            dueText: t.dueAt ? 'due ' + formatDateTime(t.dueAt) : 'no due time',
            buttonVariant: t.severity === 'Critical' ? 'destructive' : 'neutral',
            filter: t.category === 'Device' ? 'device' : t.severity === 'Critical' ? 'critical' : 'health'
        }));
    }

    get hasTodo() {
        return this.todo.length > 0;
    }

    handleKpi(event) {
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
